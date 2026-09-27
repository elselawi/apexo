/// Credentials for the live backend, passed in as dart-defines:
///
/// ```bash
/// flutter test integration_test/integration.dart -d windows \
///   --dart-define=PB_SERVER=https://pb.example.com \
///   --dart-define=PB_EMAIL=admin@example.com \
///   --dart-define=PB_PASSWORD=secret
/// ```
///
/// `tools/run_e2e.ps1` fills these three in from `test/secret.dart` for you.
///
/// They cannot be read from that file directly: a web build only compiles the
/// files under `integration_test/` and `lib/`, so a web run cannot read
/// `test/secret.dart` at all ("Error when reading
/// 'org-dartlang-app:///test/secret.dart': File not found"). Dart-defines are
/// the one mechanism that works on both.
library;

const String pbServer = String.fromEnvironment('PB_SERVER');
const String pbEmail = String.fromEnvironment('PB_EMAIL');
const String pbPassword = String.fromEnvironment('PB_PASSWORD');

/// Whether a backend to test against was configured for this run.
bool get hasCredentials =>
    pbServer.isNotEmpty && pbEmail.isNotEmpty && pbPassword.isNotEmpty;
