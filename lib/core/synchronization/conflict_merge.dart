/// Field names that store image filenames in the model JSON.  These are
/// reconciled against the server's actual file list during merge instead
/// of being union/LWW-merged, because PocketBase's `imgs` column is the
/// authoritative source of which files exist.
const _imageFields = ['imgs', 'dcmImgs'];

/// Map fields (tooth notes, drawings) that are merged per-key with
/// last-writer-wins for same-key conflicts.  This lets two devices edit
/// *different* keys (e.g. different teeth) without losing either edit.
const _mapFields = ['teeth', 'teethExtraNotes', 'drawings'];

/// List fields that are merged by union with dedup.  Only fields whose
/// semantics are additive (multi-assignment) belong here.
const _unionListFields = ['operatorsIDs'];

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
/// - **Map fields** (`teeth`, `teethExtraNotes`, `drawings`): per-key
///   LWW — different keys survive from both sides; same-key conflict
///   resolved by [localWins].
/// - **`operatorsIDs`**: union with dedup (additive semantics).
/// - **`tags`/`prescriptions`**: whole-field LWW (no merge).
///
/// [localJson]/[remoteJson] are the full `toJson()` output for each
/// side.  [localWins] selects the winner for same-field/same-key
/// conflicts.  [serverFiles] is the list of filenames PB actually has
/// for this record (may be empty).  [pendingUploads] is the set of
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

    // ── Map fields: per-key LWW ──
    if (_mapFields.contains(key)) {
      final localMap = _toStringMap(localVal);
      final remoteMap = _toStringMap(remoteVal);
      // Winner's keys win for same-key conflicts; loser's distinct
      // keys survive.  This preserves deletions on the winning side
      // (a deleted key is simply absent from the winner's map).
      final mapKeys = <String>{...localMap.keys, ...remoteMap.keys};
      final mergedMap = <String, String>{};
      for (final mk in mapKeys) {
        if (winner.containsKey(key) && winner[key] is Map) {
          // Winner takes precedence for keys it has.
          final wMap = _toStringMap(winner[key]);
          if (wMap.containsKey(mk)) {
            mergedMap[mk] = wMap[mk]!;
            continue;
          }
        }
        // Otherwise take from whichever side has it.
        if (localMap.containsKey(mk)) {
          mergedMap[mk] = localMap[mk]!;
        } else if (remoteMap.containsKey(mk)) {
          mergedMap[mk] = remoteMap[mk]!;
        }
      }
      if (mergedMap.isNotEmpty) merged[key] = mergedMap;
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

    // ── LWW list fields (tags, prescriptions) & all other scalars ──
    // Whole-field LWW: take the winner's value if present, else the
    // loser's.  This also covers `date` (always present → winner wins)
    // and scalar fields like `name`/`phone`/`age`.
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