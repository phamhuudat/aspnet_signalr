import 'dart:async';

import '../../core/logger.dart';
import '../../domain/entities/server_message.dart';
import '../../domain/repositories/client_transport.dart';
import '../protocol/message_parser.dart';

/// Shared bookkeeping of the concrete transports.
///
/// Every `connect` starts a new generation; events of older generations
/// (a socket that is still closing) are ignored.
abstract class TransportBase implements ClientTransport {
  /// Creates the base.
  TransportBase({required this.logger, this.parser = const MessageParser()});

  /// Logger.
  final SignalRLogger logger;

  /// Frame parser.
  final MessageParser parser;

  int _generation = 0;
  MessageHandler? _onMessage;
  CloseHandler? _onClose;
  Completer<void>? _init;
  bool _lost = false;

  /// Current generation.
  int get generation => _generation;

  /// Starts a new generation and returns it.
  int beginSession(
    MessageHandler onMessage,
    CloseHandler onClose, {
    required bool waitForInit,
  }) {
    _generation++;
    _onMessage = onMessage;
    _onClose = onClose;
    _lost = false;
    _init = waitForInit ? Completer<void>() : null;
    return _generation;
  }

  /// Completes when the init message arrives (no-op if not waiting).
  Future<void> get initialized => _init?.future ?? Future.value();

  /// Invalidates the current generation (used by `close`).
  void endSession() {
    _generation++;
    final init = _init;
    _init = null;
    if (init != null && !init.isCompleted) {
      init.completeError(StateError('Transport closed'));
      init.future.ignore();
    }
  }

  /// Parses and delivers a raw frame of generation [gen].
  void handleRaw(int gen, String raw) {
    if (gen != _generation) return;
    logger.log(LogLevel.trace, '<- $raw');
    final ServerMessage? message;
    try {
      message = parser.parse(raw);
    } catch (e) {
      logger.log(LogLevel.warning, 'Dropping invalid frame', e);
      return;
    }
    if (message != null) deliver(gen, message);
  }

  /// Delivers a parsed message of generation [gen].
  void deliver(int gen, ServerMessage message) {
    if (gen != _generation) return;
    final init = _init;
    _onMessage?.call(message);
    if (init != null &&
        !init.isCompleted &&
        message is PersistentResponse &&
        message.initialized) {
      init.complete();
    }
  }

  /// Reports that the channel of generation [gen] was lost.
  void handleLost(int gen, Object? error) {
    if (gen != _generation || _lost) return;
    _lost = true;
    final init = _init;
    if (init != null && !init.isCompleted) {
      init.completeError(error ?? StateError('Transport closed during init'));
      return;
    }
    logger.log(LogLevel.debug, '$type transport lost', error);
    _onClose?.call(error);
  }
}
