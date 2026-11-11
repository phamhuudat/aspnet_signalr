import 'dart:async';

import '../../domain/entities/connection_info.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/exceptions/signalr_exception.dart';
import '../../domain/repositories/client_transport.dart';
import '../datasources/signalr_http_datasource.dart';
import '../network/error_mapper.dart';
import '../protocol/message_parser.dart';
import '../protocol/url_builder.dart';
import 'sse/sse_connection.dart';
import 'sse/sse_connector.dart';
import 'transport_base.dart';

/// Server-Sent Events transport. Receives on an event stream, sends with
/// `POST /send`.
class ServerSentEventsTransport extends TransportBase {
  /// Creates the transport.
  ServerSentEventsTransport({
    required this.urls,
    required this.dataSource,
    required super.logger,
    this.headers = const {},
  });

  /// URL builder.
  final SignalRUrlBuilder urls;

  /// HTTP data source (send).
  final SignalRHttpDataSource dataSource;

  /// Extra headers.
  final Map<String, String> headers;

  SseConnection? _connection;
  StreamSubscription<String>? _sub;
  ConnectionInfo? _info;

  @override
  TransportType get type => TransportType.serverSentEvents;

  @override
  Future<void> connect(
    ConnectionInfo info, {
    required MessageHandler onMessage,
    required CloseHandler onClose,
    ReconnectCursor? reconnect,
  }) async {
    await _closeStream();
    _info = info;
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
    final SseConnection connection;
    try {
      connection = await openSseConnection(
        uri,
        http: dataSource.http,
        headers: headers,
      );
    } catch (e) {
      endSession();
      throw mapNetworkError(
        e,
        http: dataSource.http,
        uri: uri,
        fallback: (e) => TransportException('SSE connect failed', cause: e),
      );
    }
    if (gen != generation) {
      await connection.close();
      throw const TransportException('Transport closed while connecting');
    }
    _connection = connection;
    _sub = connection.events.listen(
      (data) {
        if (data == sseInitializedMarker) return;
        handleRaw(gen, data);
      },
      onError: (Object e) => handleLost(gen, e),
      onDone: () => handleLost(
        gen,
        const TransportException('Event stream closed by the server'),
      ),
    );
    await initialized;
  }

  @override
  Future<void> send(String payload) async {
    final info = _info;
    if (info == null || _connection == null) {
      throw const TransportException('SSE transport is not connected');
    }
    final gen = generation;
    final body = await dataSource.send(type, info, payload);
    handleRaw(gen, body);
  }

  Future<void> _closeStream() async {
    final sub = _sub;
    final connection = _connection;
    _sub = null;
    _connection = null;
    await sub?.cancel();
    await connection?.close();
  }

  @override
  Future<void> close() async {
    endSession();
    await _closeStream();
  }
}
