/// Web/non-IO fallback for Windows toast ids: the import must stay compilable on
/// web, where the real Hive-backed allocator cannot be used.
const int maxWindowsNotificationId = 0x7fffffff;

Future<int> nextWindowsNotificationId() {
  return Future<int>.error(
    UnsupportedError('Windows notification ids are only available on Windows.'),
  );
}
