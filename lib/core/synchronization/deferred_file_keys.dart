// Deferred FILE keys: uploads are `FILE||rowID||path||filename[||retries]`;
// deletes are `FILE||rowID||filename` with value 0.
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

int parseDeferredRetries(String key) {
  final parts = key.split('||');
  if (parts.length >= 5) return int.tryParse(parts[4]) ?? 0;
  return 0;
}

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

Set<String> filenamesFromDeferred(Map<String, int> deferred) {
  return deferred.entries
      .where((entry) => isValidDeferredFileKey(entry.key, entry.value))
      .where((entry) => entry.value == 1)
      .map((entry) => entry.key.split('||')[3])
      .toSet();
}

/// Deferred upload filenames for one row. Cleanup must not let a file queued
/// for another row protect a missing file here.
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
