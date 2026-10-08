// Encoding helpers for the existing deferred attachment journal.
//
// Returns whether a deferred FILE key has a supported shape and value.
// Uploads use `FILE||rowID||path||filename[||retries]`; deletes use
// `FILE||rowID||filename` and carry value 0.
bool isValidDeferredFileKey(String key, int value) {
  final parts = key.split('||');
  if (!key.startsWith('FILE||') || parts.length < 3 || parts[1].isEmpty) {
    return false;
  }
  if (value == 0) return parts.length == 3 && parts[2].isNotEmpty;
  if (value != 1 ||
      (parts.length != 4 && parts.length != 5) ||
      parts[2].isEmpty ||
      parts[3].isEmpty) {
    return false;
  }
  if (parts.length == 5 && (int.tryParse(parts[4]) ?? -1) < 0) {
    return false;
  }
  return true;
}

/// Returns the retry count embedded in a deferred FILE key, or 0 for
/// legacy 4-segment keys.  Format: `FILE||rowID||path||filename||retries`.
int parseDeferredRetries(String key) {
  final parts = key.split('||');
  if (parts.length >= 5) return int.tryParse(parts[4]) ?? 0;
  return 0;
}

/// Builds a new deferred FILE key with [newRetries] substituted into the
/// retries slot.  Legacy 4-segment keys grow a 5th segment; 5+-segment
/// keys overwrite the last segment.
String buildDeferredRetryKey(String key, int newRetries) {
  final parts = key.split('||');
  final next = newRetries.toString();
  if (parts.length > 4) {
    parts[4] = next;
  } else {
    parts.add(next);
  }
  return parts.join('||');
}

/// Extracts the filename (segment index 3) from every `FILE||…` key in
/// [deferred] whose value indicates an upload (value == 1).  Delete
/// entries (value == 0 / 3-segment keys) produce empty strings and are
/// harmless in the returned set.
///
/// Used by [DicomController._healDanglingDcmImgs] to skip filenames that
/// are currently queued for upload.
Set<String> filenamesFromDeferred(Map<String, int> deferred) {
  return deferred.entries
      .where((entry) => isValidDeferredFileKey(entry.key, entry.value))
      .where((entry) => entry.value == 1)
      .map((entry) => entry.key.split('||')[3])
      .toSet();
}

/// Returns deferred upload filenames belonging to one model row.
///
/// Cleanup must scope this check to the appointment being inspected. A
/// filename queued for another row must not protect a missing file here.
Set<String> filenamesFromDeferredForRow(
    Map<String, int> deferred, String rowID) {
  return deferred.entries
      .where((entry) =>
          isValidDeferredFileKey(entry.key, entry.value) &&
          entry.value == 1 &&
          entry.key.startsWith('FILE||$rowID||'))
      .map((entry) => entry.key.split('||')[3])
      .toSet();
}
