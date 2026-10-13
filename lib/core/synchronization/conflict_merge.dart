/// Field names that store image filenames in the model JSON.  These are
/// reconciled against the server's actual file list during merge instead
/// of being union/LWW-merged, because PocketBase's `imgs` column is the
/// authoritative source of which files exist.
const _imageFields = ['imgs', 'dcmImgs'];

/// Deletion-capable map fields whose winning snapshot is authoritative.
const _mapFields = ['teeth', 'teethExtraNotes', 'drawings'];

/// List fields that are merged by union with dedup.  Only fields whose
/// semantics are additive (multi-assignment) belong here.
const _unionListFields = ['operatorsIDs'];

/// Deletion-capable lists, including defaults omitted by model serialization.
const _lwwListFields = ['tags', 'prescriptions'];

/// Merges two JSON representations of the same record after a sync
/// conflict, instead of discarding one entire version.
///
/// Strategies per field type (see the field sets above):
/// - **Scalar fields**: union — a field present on one side (and
///   default-absent on the other) is kept.  When both sides have a
///   non-default value that differs, last-write-wins by [localWins].
/// - **`imgs`/`dcmImgs`**: reconciled against [serverFiles] (the PB
///   `imgs` column), which is the authoritative source of which files
///   exist.  Filenames in [pendingUploads] are kept even if not yet on
///   the server (deferred uploads).
/// - **Map fields** (`teeth`, `teethExtraNotes`, `drawings`): whole-field
///   LWW — only the winner's entries survive; an omitted map is empty.
/// - **`operatorsIDs`**: union with dedup (additive semantics).
/// - **`tags`/`prescriptions`**: whole-field LWW; an omitted list is empty.
///
/// No common ancestor or per-key deletion history is available. A loser-only
/// entry could be an addition or an entry deleted by the winner; these cannot
/// be distinguished from two snapshots. Deletion-capable collections therefore
/// use the winner's entire snapshot, intentionally discarding losing additions
/// rather than risking resurrection. Omitting a default collection must not
/// fall back to the losing value.
///
/// [localJson]/[remoteJson] are the full `toJson()` output for each
/// side, not patches. [localWins] selects the authoritative collection snapshot
/// and resolves same-field scalar conflicts. [serverFiles] lists filenames PB
/// actually has for this record (may be empty). [pendingUploads] contains
/// filenames queued for deferred upload to this record.
///
/// Returns the merged JSON map.
Map<String, dynamic> mergeConflict({
  required Map<String, dynamic> localJson,
  required Map<String, dynamic> remoteJson,
  required bool localWins,
  List<String> serverFiles = const [],
  Set<String> pendingUploads = const {},
}) {
  final winner = localWins ? localJson : remoteJson;
  final loser = localWins ? remoteJson : localJson;
  final merged = <String, dynamic>{};

  // Union of all keys across both sides.
  final allKeys = <String>{...localJson.keys, ...remoteJson.keys};

  for (final key in allKeys) {
    // `id` is always present and identical — take it from either side.
    if (key == 'id') {
      merged['id'] = localJson['id'] ?? remoteJson['id'];
      continue;
    }

    final localVal = localJson[key];
    final remoteVal = remoteJson[key];

    // ── Image fields: reconcile against the server's actual files ──
    if (_imageFields.contains(key)) {
      merged[key] = _mergeImageField(
        localVal: localVal,
        remoteVal: remoteVal,
        serverFiles: serverFiles,
        pendingUploads: pendingUploads,
        isDcm: key == 'dcmImgs',
      );
      continue;
    }

    // ── Deletion-capable maps: authoritative winner snapshot ──
    if (_mapFields.contains(key)) {
      final winnerMap = _toStringMap(winner[key]);
      if (winnerMap.isNotEmpty) merged[key] = winnerMap;
      continue;
    }

    // ── Whole-list LWW: omitted defaults must stay omitted ──
    if (_lwwListFields.contains(key)) {
      if (winner.containsKey(key)) merged[key] = winner[key];
      continue;
    }

    // ── Union list fields (operatorsIDs): union with dedup ──
    if (_unionListFields.contains(key)) {
      final localList = _toStringList(localVal);
      final remoteList = _toStringList(remoteVal);
      final union = <String>{
        ...localList,
        ...remoteList,
      }.toList();
      if (union.isNotEmpty) merged[key] = union;
      continue;
    }

    // ── Other fields: winner when present, otherwise loser ──
    // This covers `date` (always present → winner wins) and preserves
    // existing default-absent scalar behavior for `name`/`phone`/`age`.
    if (winner.containsKey(key)) {
      merged[key] = winner[key];
    } else if (loser.containsKey(key)) {
      merged[key] = loser[key];
    }
  }

  return merged;
}

/// Merges an image-filename list field (`imgs`/`dcmImgs`) by taking the
/// union of local and remote model lists, then keeping only filenames
/// that either (a) exist on the server ([serverFiles]) or (b) are
/// pending upload ([pendingUploads]).  [isDcm] filters the server list
/// to DICOM vs regular images.
List<String> _mergeImageField({
  required Object? localVal,
  required Object? remoteVal,
  required List<String> serverFiles,
  required Set<String> pendingUploads,
  required bool isDcm,
}) {
  final localList = _toStringList(localVal);
  final remoteList = _toStringList(remoteVal);
  final candidates = <String>{...localList, ...remoteList};

  // The server's `imgs` column holds BOTH regular images and DICOM
  // files in one list.  Filter to the relevant subtype.
  final serverRelevant = serverFiles
      .where(isDcm ? _isDcmFileStatic : _isNotDcmFileStatic)
      .map((name) => name.toLowerCase())
      .toSet();
  final pendingUploadNames =
      pendingUploads.map((name) => name.toLowerCase()).toSet();

  final kept = <String>[];
  for (final name in candidates) {
    // Keep if the server actually has the file, or if it's pending
    // upload (deferred FILE entry not yet processed). PocketBase filenames
    // are treated case-insensitively throughout the DICOM paths.
    final lowerName = name.toLowerCase();
    if (serverRelevant.contains(lowerName) ||
        pendingUploadNames.contains(lowerName)) {
      kept.add(name);
    }
  }
  return kept;
}

bool _isDcmFileStatic(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.dcm') || lower.endsWith('.dicom');
}

bool _isNotDcmFileStatic(String name) => !_isDcmFileStatic(name);

Map<String, String> _toStringMap(Object? val) {
  if (val is Map) {
    return val.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  return {};
}

List<String> _toStringList(Object? val) {
  if (val is List) {
    return val.map((e) => e.toString()).toList();
  }
  return [];
}