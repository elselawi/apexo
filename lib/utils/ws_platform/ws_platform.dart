import 'ws_platform_stub.dart' if (dart.library.html) 'ws_platform_web.dart';

/// Re-exports the platform-appropriate [connectWebSocket].
///
/// - Native (non-web): uses `IOWebSocketChannel` with custom headers.
/// - Web: uses `HtmlWebSocketChannel` with token passed as query parameter.
export 'ws_platform_stub.dart' if (dart.library.html) 'ws_platform_web.dart';
