import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web WebSocket connection using the browser's native WebSocket.
///
/// Browser WebSockets do not support custom headers, so the Authorization
/// token is passed as a query parameter (`?token=...`) instead.
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

  debugPrint('[WSVoice] 🌐 WebSocket URL: $webUri');
  return HtmlWebSocketChannel.connect(webUri);
}
