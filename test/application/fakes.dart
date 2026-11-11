import 'dart:async';

import 'package:aspnet_signalr/src/domain/entities/connection_info.dart';
import 'package:aspnet_signalr/src/domain/entities/server_message.dart';
import 'package:aspnet_signalr/src/domain/entities/transport_type.dart';
import 'package:aspnet_signalr/src/domain/repositories/client_transport.dart';
import 'package:aspnet_signalr/src/domain/repositories/connection_session.dart';
import 'package:aspnet_signalr/src/domain/repositories/negotiation_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockNegotiation extends Mock implements NegotiationRepository {}

/// Scriptable in-memory transport.
class FakeTransport implements ClientTransport {
  FakeTransport(this.type);

  @override
  final TransportType type;

  MessageHandler? onMessage;
  CloseHandler? onClose;
  final sent = <String>[];
  final reconnects = <ReconnectCursor>[];
  int connects = 0;
  int closes = 0;

  /// Error thrown by the next connect calls.
  Object? connectError;

  /// Called on each send; may reply.
  void Function(String payload)? onSend;

  @override
  Future<void> connect(
    ConnectionInfo info, {
    required MessageHandler onMessage,
    required CloseHandler onClose,
    ReconnectCursor? reconnect,
  }) async {
    connects++;
    if (reconnect != null) reconnects.add(reconnect);
    final err = connectError;
    if (err != null) throw err;
    this.onMessage = onMessage;
    this.onClose = onClose;
    if (reconnect == null) {
      onMessage(const PersistentResponse(messageId: 'c0', initialized: true));
    }
  }

  void receive(ServerMessage m) => onMessage!(m);

  void drop([Object? error]) => onClose!(error);

  @override
  Future<void> send(String payload) async {
    sent.add(payload);
    onSend?.call(payload);
  }

  @override
  Future<void> close() async => closes++;
}

class FakeSession implements ConnectionSession {
  FakeSession(this.negotiation, this.transport);

  @override
  final NegotiationRepository negotiation;
  final FakeTransport transport;
  bool disposed = false;
  List<String> hubs = const [];

  @override
  ClientTransport createTransport(TransportType type) => transport;

  @override
  void dispose() => disposed = true;
}

class FakeSessionFactory implements ConnectionSessionFactory {
  FakeSessionFactory(this.make);

  final FakeSession Function() make;
  final sessions = <FakeSession>[];

  @override
  ConnectionSession create(List<String> hubNames) {
    final s = make()..hubs = hubNames;
    sessions.add(s);
    return s;
  }
}
