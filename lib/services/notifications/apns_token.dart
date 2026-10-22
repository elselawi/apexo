/// Reads the APNs device token — `FirebaseMessaging.getAPNSToken` in
/// production.
typedef ApnsTokenReader = Future<String?> Function();

/// How many times [waitForAPNSToken] reads the token, and the pause between
/// reads — five seconds in total, long enough to cover the system's first
/// registration with APNs on a cold start.
const int apnsTokenAttempts = 10;
const Duration apnsTokenRetryInterval = Duration(milliseconds: 500);

/// Waits for the APNs token that iOS and macOS need before FCM will issue an
/// FCM token.
///
/// The system registers with APNs asynchronously after the app launches, so a
/// single read straight after asking for permission usually returns `null`.
/// This reads up to [attempts] times, [interval] apart, and returns the first
/// token it sees — or `null` if none arrives, leaving the FCM token-refresh
/// listener to pick the token up later.
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
