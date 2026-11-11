import 'dart:async';

import '../../domain/entities/connection_info.dart';
import '../../domain/entities/server_message.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/exceptions/signalr_exception.dart';
import '../../domain/repositories/client_transport.dart';
import '../datasources/signalr_http_datasource.dart';
import '../protocol/url_builder.dart';
import 'transport_base.dart';

/// Long polling transport: `POST /connect`, then a loop of `POST /poll`.
class LongPollingTransport extends TransportBase {
  /// Creates the transport.
  LongPollingTransport({
    required this.urls,
    required this.dataSource,
    required super.logger,
    this.reconnectedDelay = const Duration(seconds: 3),
  });

  /// URL builder.
  final SignalRUrlBuilder urls;

  /// HTTP data source.
  final SignalRHttpDataSource dataSource;

  /// After `/reconnect` is sent without error for this long, the reconnect
  /// is considered successful (same as the JavaScript client).
  final Duration reconnectedDelay;

  ConnectionInfo? _info;
  String? _messageId;
  String? _groupsToken;
  Duration? _delay;

  @override
  TransportType get type => TransportType.longPolling;

  void _track(ServerMessage m) {
    if (m is PersistentResponse) {
      if (m.messageId != null) _messageId = m.messageId;
      if (m.groupsToken != null) _groupsToken = m.groupsToken;
      if (m.longPollDelay != null) _delay = m.longPollDelay;
    }
  }

  @override
  Future<void> connect(
    ConnectionInfo info, {
    required MessageHandler onMessage,
    required CloseHandler onClose,
    ReconnectCursor? reconnect,
  }) async {
    endSession();
    _info = info;
    _delay = info.longPollDelay;
    void tracking(ServerMessage m) {
      _track(m);
      onMessage(m);
    }

    final gen = beginSession(tracking, onClose, waitForInit: reconnect == null);
    if (reconnect == null) {
      final String body;
      try {
        body = await dataSource.postForBody(urls.connect(type, info));
      } catch (e) {
        endSession();
        rethrow;
      }
      handleRaw(gen, body);
      await initialized;
      unawaited(_loop(gen, first: null));
      return;
    }
    _messageId = reconnect.messageId;
    _groupsToken = reconnect.groupsToken;
    final ready = Completer<void>();
    final timer = Timer(reconnectedDelay, () {
      if (!ready.isCompleted) ready.complete();
    });
    unawaited(_loop(gen, first: ready));
    try {
      await ready.future;
    } finally {
      timer.cancel();
    }
  }

  Future<void> _loop(int gen, {required Completer<void>? first}) async {
    var reconnecting = first != null;
    while (gen == generation) {
      final info = _info!;
      final uri = reconnecting
          ? urls.reconnect(
              type,
              info,
              messageId: _messageId,
              groupsToken: _groupsToken,
            )
          : urls.poll(info, messageId: _messageId, groupsToken: _groupsToken);
      final String body;
      try {
        body = await dataSource.postForBody(uri);
      } catch (e) {
        if (first != null && !first.isCompleted) {
          first.completeError(e);
          endSession();
        } else {
          handleLost(gen, e);
        }
        return;
      }
      if (gen != generation) return;
      if (first != null && !first.isCompleted) first.complete();
      reconnecting = false;
      handleRaw(gen, body);
      final delay = _delay ?? Duration.zero;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    }
  }

  @override
  Future<void> send(String payload) async {
    final info = _info;
    if (info == null) {
      throw const TransportException('Long polling is not connected');
    }
    final gen = generation;
    final body = await dataSource.send(type, info, payload);
    handleRaw(gen, body);
  }

  @override
  Future<void> close() async => endSession();
}
