import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket via the browser's native WebSocket. Browsers cannot send custom
/// headers, so the bearer token goes in a `?token=` query parameter.
WebSocketChannel connectWebSocket(
  Uri uri,
  Map<String, String> headers,
) {
  // Merge headers into query parameters — the only way to pass auth on web.
  final queryParams = Map<String, String>.from(uri.queryParameters);
  final authHeader = headers['Authorization'];
  if (authHeader != null && authHeader.startsWith('Bearer ')) {
    queryParams['token'] = authHeader.substring(7);
  }
  final webUri = uri.replace(queryParameters: queryParams);

  return HtmlWebSocketChannel.connect(webUri);
}
