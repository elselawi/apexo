import 'ws_platform_stub.dart' if (dart.library.html) 'ws_platform_web.dart';

/// Re-exports the platform-appropriate [connectWebSocket].
export 'ws_platform_stub.dart' if (dart.library.html) 'ws_platform_web.dart';
