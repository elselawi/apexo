/// Web/non-IO fallback for Windows toast ids.
///
/// Windows is the only platform that calls this, but the import must stay
/// compilable on web; the real allocator uses Hive and the filesystem.
const int maxWindowsNotificationId = 0x7fffffff;

Future<int> nextWindowsNotificationId() {
  return Future<int>.error(
    UnsupportedError('Windows notification ids are only available on Windows.'),
  );
}
