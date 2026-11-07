/// Reads the APNs device token; production uses `FirebaseMessaging.getAPNSToken`.
typedef ApnsTokenReader = Future<String?> Function();

/// 10 × 500 ms = 5 s, enough to cover APNs' first registration on a cold start.
const int apnsTokenAttempts = 10;
const Duration apnsTokenRetryInterval = Duration(milliseconds: 500);

/// Polls for the APNs token iOS/macOS need before FCM issues one, since
/// registration is async; gives up after [attempts] for the refresh listener.
Future<String?> waitForAPNSToken(
  ApnsTokenReader readToken, {
  int attempts = apnsTokenAttempts,
  Duration interval = apnsTokenRetryInterval,
  Future<void> Function(Duration) wait = _delay,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final token = await readToken();
    if (token != null && token.isNotEmpty) return token;
    if (attempt < attempts - 1) await wait(interval);
  }
  return null;
}

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);
