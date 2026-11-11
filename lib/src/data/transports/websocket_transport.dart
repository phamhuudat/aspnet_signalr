import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/connection_info.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/exceptions/signalr_exception.dart';
import '../../domain/repositories/client_transport.dart';
import '../network/error_mapper.dart';
import '../network/signalr_http_client.dart';
import '../protocol/url_builder.dart';
import 'transport_base.dart';
import 'ws/ws_connector.dart';

/// WebSockets transport. Sends frames on the socket.
class WebSocketTransport extends TransportBase {
  /// Creates the transport.
  WebSocketTransport({
    required this.urls,
    required this.http,
    required super.logger,
    this.headers = const {},
  });

  /// URL builder.
  final SignalRUrlBuilder urls;

  /// HTTP resources (the proxied `HttpClient`).
  final SignalRHttpClient http;

  /// Extra headers (ignored on the Web).
  final Map<String, String> headers;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;

  @override
  TransportType get type => TransportType.webSockets;

  @override
  Future<void> connect(
    ConnectionInfo info, {
    required MessageHandler onMessage,
    required CloseHandler onClose,
    ReconnectCursor? reconnect,
  }) async {
    await _closeChannel();
    final gen =
        beginSession(onMessage, onClose, waitForInit: reconnect == null);
    final uri = reconnect == null
        ? urls.connect(type, info)
        : urls.reconnect(
            type,
            info,
            messageId: reconnect.messageId,
            groupsToken: reconnect.groupsToken,
          );
    final WebSocketChannel channel;
    try {
      channel = await connectWebSocket(uri, http: http, headers: headers);
    } catch (e) {
      endSession();
      throw mapNetworkError(
        e,
        http: http,
        uri: uri,
        fallback: (e) =>
            TransportException('WebSocket connect failed', cause: e),
      );
    }
    if (gen != generation) {
      await channel.sink.close();
      throw const TransportException('Transport closed while connecting');
    }
    _channel = channel;
    _sub = channel.stream.listen(
      (data) => handleRaw(gen, data is String ? data : '$data'),
      onError: (Object e) => handleLost(gen, e),
      onDone: () => handleLost(
        gen,
        TransportException('WebSocket closed (${channel.closeCode})'),
      ),
    );
    await initialized;
  }

  @override
  Future<void> send(String payload) async {
    final channel = _channel;
    if (channel == null) {
      throw const TransportException('WebSocket is not connected');
    }
    channel.sink.add(payload);
  }

  Future<void> _closeChannel() async {
    final sub = _sub;
    final channel = _channel;
    _sub = null;
    _channel = null;
    await sub?.cancel();
    if (channel != null) {
      unawaited(channel.sink.close(1000).catchError((_) {}));
    }
  }

  @override
  Future<void> close() async {
    endSession();
    await _closeChannel();
  }
}
