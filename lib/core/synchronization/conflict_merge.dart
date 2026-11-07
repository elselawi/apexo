// Image fields are reconciled against PocketBase's `imgs` column, the
// authoritative list of files, instead of being union/LWW-merged.
const _imageFields = ['imgs', 'dcmImgs'];

/// Deletion-capable map fields whose winning snapshot is authoritative.
const _mapFields = ['teeth', 'teethExtraNotes', 'drawings'];

// Only fields with additive (multi-assignment) semantics belong here.
const _unionListFields = ['operatorsIDs'];

/// Deletion-capable lists, including defaults omitted by model serialization.
const _lwwListFields = ['tags', 'prescriptions'];

/// Merges two full `toJson()` snapshots of the same record after a sync
/// conflict. Deletion-capable collections take the whole winning snapshot: a
/// loser-only entry may be a deletion, and merging it back would resurrect it.
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

    if (winner.containsKey(key)) {
      merged[key] = winner[key];
    } else if (loser.containsKey(key)) {
      merged[key] = loser[key];
    }
  }

  return merged;
}

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

  // PB's `imgs` column holds regular images and DICOM files in one list.
  final serverRelevant = serverFiles
      .where(isDcm ? _isDcmFileStatic : _isNotDcmFileStatic)
      .map((name) => name.toLowerCase())
      .toSet();
  final pendingUploadNames =
      pendingUploads.map((name) => name.toLowerCase()).toSet();

  final kept = <String>[];
  for (final name in candidates) {
    // PocketBase filenames are compared case-insensitively throughout.
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