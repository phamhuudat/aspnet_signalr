import 'dart:async';

import '../../core/logger.dart';
import '../../domain/entities/connection_info.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/exceptions/signalr_exception.dart';
import '../../domain/repositories/client_transport.dart';

/// Creates a concrete transport.
typedef TransportFactory = ClientTransport Function(TransportType type);

/// Tries WebSockets (if the server allows it), then Server-Sent Events,
/// then long polling. Each step is limited by `TransportConnectTimeout`.
class AutoTransport implements ClientTransport {
  /// Creates the transport.
  AutoTransport({
    required this.factory,
    required this.logger,
    this.order = const [
      TransportType.webSockets,
      TransportType.serverSentEvents,
      TransportType.longPolling,
    ],
  });

  /// Creates concrete transports.
  final TransportFactory factory;

  /// Logger.
  final SignalRLogger logger;

  /// Fallback order.
  final List<TransportType> order;

  ClientTransport? _selected;

  @override
  TransportType get type => _selected?.type ?? TransportType.auto;

  @override
  Future<void> connect(
    ConnectionInfo info, {
    required MessageHandler onMessage,
    required CloseHandler onClose,
    ReconnectCursor? reconnect,
  }) async {
    final selected = _selected;
    if (reconnect != null && selected != null) {
      return selected.connect(
        info,
        onMessage: onMessage,
        onClose: onClose,
        reconnect: reconnect,
      );
    }
    await selected?.close();
    _selected = null;
    Object? lastError;
    for (final candidate in order) {
      if (candidate == TransportType.webSockets && !info.tryWebSockets) {
        logger.log(LogLevel.debug, 'Server disabled WebSockets, skipping');
        continue;
      }
      final transport = factory(candidate);
      try {
        logger.log(LogLevel.debug, 'Trying ${candidate.name}');
        await transport
            .connect(info, onMessage: onMessage, onClose: onClose)
            .timeout(info.transportConnectTimeout);
        _selected = transport;
        logger.log(LogLevel.info, 'Connected with ${candidate.name}');
        return;
      } on ProxyException {
        await transport.close();
        rethrow;
      } catch (e) {
        lastError = e is TimeoutException
            ? SignalRTimeoutException('${candidate.name} timed out')
            : e;
        logger.log(LogLevel.info, '${candidate.name} failed', lastError);
        await transport.close();
      }
    }
    throw TransportException('No transport could connect', cause: lastError);
  }

  @override
  Future<void> send(String payload) {
    final selected = _selected;
    if (selected == null) {
      throw const TransportException('Not connected');
    }
    return selected.send(payload);
  }

  @override
  Future<void> close() async => _selected?.close();
}
