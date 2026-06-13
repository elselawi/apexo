import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native (non-web) WebSocket connection using dart:io.
///
/// Supports custom headers (e.g. Authorization).
WebSocketChannel connectWebSocket(
  Uri uri,
  Map<String, String> headers,
) {
  return IOWebSocketChannel.connect(uri, headers: headers);
}
