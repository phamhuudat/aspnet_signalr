import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../network/signalr_http_client.dart';

/// Opens a WebSocket through the session `HttpClient` (proxy aware).
Future<WebSocketChannel> connectWebSocket(
  Uri uri, {
  required SignalRHttpClient http,
  Map<String, String> headers = const {},
}) async {
  final native = http.nativeClient;
  final channel = IOWebSocketChannel.connect(
    uri,
    headers: headers.isEmpty ? null : headers,
    customClient: native is HttpClient ? native : null,
  );
  await channel.ready;
  return channel;
}
