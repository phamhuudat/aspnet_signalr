import 'dart:async';
import 'dart:convert';

import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:aspnet_signalr/src/application/hub_connection_impl.dart';
import 'package:aspnet_signalr/src/domain/entities/connection_info.dart';
import 'package:aspnet_signalr/src/domain/entities/hub_message.dart';
import 'package:aspnet_signalr/src/domain/entities/server_message.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(TransportType.auto);
    registerFallbackValue(
      const ConnectionInfo(connectionId: '', connectionToken: ''),
    );
  });

  late MockNegotiation negotiation;
  late FakeTransport transport;
  late FakeSessionFactory factory;
  var info = const ConnectionInfo(connectionId: 'id-1', connectionToken: 't');

  setUp(() {
    info = const ConnectionInfo(
      connectionId: 'id-1',
      connectionToken: 't',
      disconnectTimeout: Duration(seconds: 30),
    );
    negotiation = MockNegotiation();
    transport = FakeTransport(TransportType.serverSentEvents);
    factory = FakeSessionFactory(() => FakeSession(negotiation, transport));
    when(() => negotiation.negotiate()).thenAnswer((_) async => info);
    when(() => negotiation.start(any(), any())).thenAnswer((_) async {});
    when(() => negotiation.abort(any(), any())).thenAnswer((_) async {});
  });

  HubConnectionImpl create({
    ReconnectPolicy? policy,
    TransportType type = TransportType.serverSentEvents,
  }) =>
      HubConnectionImpl(
        sessionFactory: factory,
        transportType: type,
        reconnectPolicy: policy,
        invocationTimeout: const Duration(milliseconds: 300),
      );

  test('start sends lower-case hub names and reaches connected', () async {
    final c = create();
    c.createHubProxy('HubA');
    c.createHubProxy('huba'); // same proxy
    final states = <ConnectionState>[];
    c.stateStream.listen(states.add);
    await c.start();
    expect(factory.sessions.single.hubs, ['huba']);
    expect(c.state, ConnectionState.connected);
    expect(c.connectionId, 'id-1');
    expect(c.transport, TransportType.serverSentEvents);
    expect(states, [ConnectionState.connecting, ConnectionState.connected]);
    verify(() => negotiation.start(TransportType.serverSentEvents, info))
        .called(1);
    expect(() => c.createHubProxy('Other'), throwsStateError);
    expect(c.start, throwsStateError);
  });

  test('dispatches hub messages case-insensitively, off removes', () async {
    final c = create();
    final hub = c.createHubProxy('HubA');
    final got = <List<dynamic>>[];
    void handler(List<dynamic> a) => got.add(a);
    hub.on('Update', handler);
    hub.on('update', (_) => throw StateError('handler errors are isolated'));
    await c.start();
    transport.receive(const PersistentResponse(messages: [
      HubMessage(hub: 'HUBA', method: 'UPDATE', args: [1]),
      HubMessage(hub: 'unknown', method: 'update', args: [2]),
    ]));
    expect(got, [
      [1],
    ]);
    hub.off('update', handler);
    transport.receive(const PersistentResponse(messages: [
      HubMessage(hub: 'HubA', method: 'update', args: [3]),
    ]));
    expect(got, hasLength(1));
    hub.off('update');
  });

  test('invoke: result, error, timeout, state', () async {
    final c = create();
    final hub = c.createHubProxy('HubA');
    transport.onSend = (payload) {
      final inv = jsonDecode(payload) as Map<String, dynamic>;
      final id = '${inv['I']}';
      switch (inv['M']) {
        case 'add':
          transport.receive(InvocationResult(id: id, result: 3));
        case 'half':
          transport.receive(InvocationResult(id: id, result: 2));
        case 'fail':
          transport.receive(InvocationResult(
            id: id,
            error: 'nope',
            errorData: 1,
            isHubException: true,
          ));
        case 'state':
          expect(inv['S'], {'n': 1});
          transport.receive(InvocationResult(id: id, state: const {'n': 2}));
      }
    };
    await c.start();
    expect(await hub.invoke<int>('add', [1, 2]), 3);
    expect(await hub.invoke<double>('half'), 2.0);
    expect(jsonDecode(transport.sent.first), {
      'H': 'huba',
      'M': 'add',
      'A': [1, 2],
      'I': 0,
    });
    await expectLater(
      hub.invoke<void>('fail'),
      throwsA(
          isA<HubInvocationException>().having((e) => e.errorData, 'data', 1)),
    );
    await expectLater(
      hub.invoke<void>('silent'),
      throwsA(isA<SignalRTimeoutException>()),
    );
    expect(c.pendingInvocations, 0);
    hub.state['n'] = 1;
    await hub.invoke<void>('state');
    expect(hub.state['n'], 2);
  });

  test('invoke before start throws', () async {
    final hub = create().createHubProxy('HubA');
    expect(() => hub.invoke<void>('x'), throwsA(isA<SignalRException>()));
  });

  test('negotiate failure leaves the connection disconnected', () async {
    when(() => negotiation.negotiate())
        .thenThrow(const NegotiateException('boom', statusCode: 500));
    final c = create();
    await expectLater(c.start(), throwsA(isA<NegotiateException>()));
    expect(c.state, ConnectionState.disconnected);
    expect(factory.sessions.single.disposed, isTrue);
  });

  test('forcing WebSockets against TryWebSockets:false throws', () async {
    final c = create(type: TransportType.webSockets);
    await expectLater(c.start(), throwsA(isA<TransportException>()));
    expect(c.state, ConnectionState.disconnected);
  });

  test('ASP.NET Core style protocol is rejected', () async {
    info = const ConnectionInfo(
      connectionId: 'x',
      connectionToken: 't',
      protocolVersion: '2.0',
    );
    when(() => negotiation.negotiate()).thenAnswer((_) async => info);
    await expectLater(create().start(), throwsA(isA<NegotiateException>()));
  });

  test('transport loss -> /reconnect with cursor, pending calls fail',
      () async {
    final c = create();
    final hub = c.createHubProxy('HubA');
    final reconnected = Completer<bool>();
    final reconnecting = <Object?>[];
    c.onReconnected(reconnected.complete);
    c.onReconnecting(reconnecting.add);
    await c.start();
    transport
        .receive(const PersistentResponse(messageId: 'c9', groupsToken: 'g1'));
    final pending = hub.invoke<void>('never');
    transport.drop('lost');
    await expectLater(pending, throwsA(isA<SignalRException>()));
    expect(await reconnected.future, isFalse);
    expect(reconnecting, ['lost']);
    expect(transport.reconnects.single.messageId, 'c9');
    expect(transport.reconnects.single.groupsToken, 'g1');
    expect(c.state, ConnectionState.connected);
    expect(factory.sessions, hasLength(1));
  });

  test('server T:1 triggers reconnect, D:1 closes', () async {
    final c = create();
    final closed = Completer<Object?>();
    c.onClosed(closed.complete);
    await c.start();
    transport.receive(const PersistentResponse(shouldReconnect: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.reconnects, hasLength(1));
    expect(c.state, ConnectionState.connected);
    transport.receive(const PersistentResponse(disconnect: true));
    expect(await closed.future, isA<SignalRException>());
    expect(c.state, ConnectionState.disconnected);
  });

  test('without a policy, gives up when the reconnect window is over',
      () async {
    info = const ConnectionInfo(
      connectionId: 'id-1',
      connectionToken: 't',
      disconnectTimeout: Duration(milliseconds: 100),
    );
    when(() => negotiation.negotiate()).thenAnswer((_) async => info);
    final c = create();
    final closed = Completer<Object?>();
    c.onClosed(closed.complete);
    await c.start();
    transport.connectError = const TransportException('down');
    transport.drop();
    expect(await closed.future.timeout(const Duration(seconds: 5)),
        isA<TransportException>());
    expect(c.state, ConnectionState.disconnected);
    expect(factory.sessions, hasLength(1));
  });

  test('with a policy, renegotiates after the window', () async {
    info = const ConnectionInfo(
      connectionId: 'id-1',
      connectionToken: 't',
      disconnectTimeout: Duration(milliseconds: 50),
    );
    when(() => negotiation.negotiate()).thenAnswer((_) async => info);
    final c = create(
      policy: const DefaultReconnectPolicy(delays: [
        Duration(milliseconds: 100),
        Duration(milliseconds: 10),
      ]),
    );
    final reconnected = Completer<bool>();
    c.onReconnected(reconnected.complete);
    await c.start();
    transport.drop();
    expect(
        await reconnected.future.timeout(const Duration(seconds: 5)), isTrue);
    expect(factory.sessions, hasLength(2));
    expect(factory.sessions.first.disposed, isTrue);
    expect(c.state, ConnectionState.connected);
  });

  test('policy gives up -> disconnected', () async {
    final c = create(policy: const DefaultReconnectPolicy(delays: []));
    final closed = Completer<Object?>();
    c.onClosed(closed.complete);
    await c.start();
    transport.drop('x');
    expect(await closed.future, 'x');
  });

  test('keep-alive: slow warning then reconnect', () async {
    info = const ConnectionInfo(
      connectionId: 'id-1',
      connectionToken: 't',
      keepAliveTimeout: Duration(milliseconds: 150),
    );
    when(() => negotiation.negotiate()).thenAnswer((_) async => info);
    final c = create();
    var slow = 0;
    c.onConnectionSlow(() => slow++);
    final reconnected = Completer<bool>();
    c.onReconnected(reconnected.complete);
    await c.start();
    await reconnected.future.timeout(const Duration(seconds: 3));
    expect(slow, 1);
    expect(transport.reconnects, isNotEmpty);
    await c.stop();
  });

  test('stop aborts, disposes, is idempotent, and cancels reconnect', () async {
    final c = create(
        policy: const ForeverReconnectPolicy(
      initialDelay: Duration(milliseconds: 20),
    ));
    final closed = <Object?>[];
    c.onClosed(closed.add);
    await c.start();
    transport.connectError = const TransportException('down');
    transport.drop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.state, ConnectionState.reconnecting);
    await c.stop();
    await c.stop();
    expect(c.state, ConnectionState.disconnected);
    expect(closed, [null]);
    verify(() => negotiation.abort(TransportType.serverSentEvents, info))
        .called(1);
    expect(factory.sessions.last.disposed, isTrue);
    final attempts = transport.connects;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(transport.connects, attempts);
  });

  test('stop during start', () async {
    final gate = Completer<ConnectionInfo>();
    when(() => negotiation.negotiate()).thenAnswer((_) => gate.future);
    final c = create();
    final starting = c.start();
    await c.stop();
    gate.complete(info);
    await expectLater(starting, throwsA(isA<SignalRException>()));
    expect(c.state, ConnectionState.disconnected);
  });
}
