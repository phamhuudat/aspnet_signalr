import 'package:web_socket_channel/web_socket_channel.dart';

import '../../network/signalr_http_client.dart';

/// Opens a browser WebSocket. Custom headers are not supported.
Future<WebSocketChannel> connectWebSocket(
  Uri uri, {
  required SignalRHttpClient http,
  Map<String, String> headers = const {},
}) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready;
  return channel;
}
