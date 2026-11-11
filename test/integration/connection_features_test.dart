import 'dart:async';

import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:test/test.dart';

import '../../tool/fake_server/fake_signalr_server.dart';

void main() {
  late FakeSignalRServer server;

  setUp(() async {
    server = FakeSignalRServer();
    await server.start();
  });

  tearDown(() => server.close());

  HubConnectionBuilder builder() =>
      HubConnectionBuilder().withUrl(server.url.toString());

  group('auto transport', () {
    test('TryWebSockets:true selects WebSockets', () async {
      final c = builder().build()..createHubProxy('HubA');
      await c.start();
      expect(c.transport, TransportType.webSockets);
      await c.stop();
    });

    test('TryWebSockets:false selects SSE without trying WebSockets', () async {
      server.tryWebSockets = false;
      final c = builder().build()..createHubProxy('HubA');
      await c.start();
      expect(c.transport, TransportType.serverSentEvents);
      expect(
        server.requestsTo('connect').map((r) => r.transport),
        ['serverSentEvents'],
      );
      await c.stop();
    });

    test('SSE blocked falls back to long polling', () async {
      server
        ..tryWebSockets = false
        ..sseEnabled = false;
      final c = builder().build();
      final hub = c.createHubProxy('HubA');
      await c.start();
      expect(c.transport, TransportType.longPolling);
      expect(await hub.invoke<int>('add', [1, 1]), 2);
      await c.stop();
    });

    test('a stuck transport times out and the next one is used', () async {
      server
        ..sendInit = false
        ..transportConnectTimeout = const Duration(milliseconds: 300);
      final c = builder().build()..createHubProxy('HubA');
      await expectLater(c.start(), throwsA(isA<TransportException>()));
      expect(
        server.requestsTo('connect').map((r) => r.transport),
        ['webSockets', 'serverSentEvents', 'longPolling'],
      );
    });

    test('forced WebSockets on a server without WebSockets', () async {
      server.tryWebSockets = false;
      final c = builder().withTransport(TransportType.webSockets).build();
      await expectLater(c.start(), throwsA(isA<TransportException>()));
      expect(server.requestsTo('connect'), isEmpty);
    });
  });

  test('negotiate failure is a NegotiateException', () async {
    server.failNegotiate = 1;
    final c = builder().build();
    await expectLater(
      c.start(),
      throwsA(
          isA<NegotiateException>().having((e) => e.statusCode, 'status', 500)),
    );
    await c.start(); // second attempt works
    await c.stop();
  });

  test('wrong URL is a NegotiateException', () async {
    final c = HubConnectionBuilder()
        .withUrl(server.url.toString(), useDefaultPath: false)
        .build();
    await expectLater(c.start(), throwsA(isA<NegotiateException>()));
  });

  test('headers and query parameters reach every request', () async {
    server.tryWebSockets = false;
    final c = HubConnectionBuilder().withUrl(
      '${server.url}/signalr',
      useDefaultPath: false,
      headers: {'Authorization': 'Bearer FAKE'},
      queryParameters: {'access_token': 'FAKE'},
    ).build()
      ..createHubProxy('HubA');
    await c.start();
    await c.stop();
    for (final r in server.requests) {
      expect(r.query['access_token'], 'FAKE', reason: '$r');
      expect(r.headers['authorization'], 'Bearer FAKE', reason: '$r');
    }
  });

  test('two hubs on one connection', () async {
    final c = builder().build();
    final a = c.createHubProxy('HubA');
    final b = c.createHubProxy('HubB');
    final got = <String>[];
    a.on('update', (args) => got.add('a:${args[0]}'));
    b.on('update', (args) => got.add('b:${args[0]}'));
    await c.start();
    expect(server.connections.values.single.hubs, ['huba', 'hubb']);
    server
      ..broadcast('HubA', 'update', [1])
      ..broadcast('HubB', 'update', [2]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(got, ['a:1', 'b:2']);
    await c.stop();
  });

  test('hub state round trip', () async {
    final c = builder().build();
    final hub = c.createHubProxy('HubA');
    await c.start();
    expect(await hub.invoke<int>('counter'), 1);
    expect(await hub.invoke<int>('counter'), 2);
    expect(hub.state['count'], 2);
    await c.stop();
  });

  test('without automatic reconnect, an expired window disconnects', () async {
    server
      ..tryWebSockets = false
      ..keepAliveTimeout = null
      ..disconnectTimeout = const Duration(milliseconds: 300)
      ..rejectReconnect = true;
    final c = builder().build()..createHubProxy('HubA');
    final closed = Completer<Object?>();
    c.onClosed(closed.complete);
    await c.start();
    await server.dropAll();
    expect(await closed.future.timeout(const Duration(seconds: 10)), isNotNull);
    expect(c.state, ConnectionState.disconnected);
  });

  test('automatic reconnect renegotiates after the window', () async {
    server
      ..tryWebSockets = false
      ..keepAliveTimeout = null
      ..disconnectTimeout = const Duration(milliseconds: 200)
      ..rejectReconnect = true;
    final c = builder().withAutomaticReconnect(delays: [
      Duration.zero,
      const Duration(milliseconds: 300),
    ]).build();
    c.createHubProxy('HubA');
    final reconnected = Completer<bool>();
    c.onReconnected(reconnected.complete);
    await c.start();
    final firstId = c.connectionId;
    await server.dropAll();
    expect(
        await reconnected.future.timeout(const Duration(seconds: 10)), isTrue);
    expect(c.connectionId, isNot(firstId));
    expect(server.requestsTo('negotiate'), hasLength(2));
    await c.stop();
  });

  test('silent server: keep-alive timeout triggers reconnect', () async {
    server
      ..keepAliveTimeout = const Duration(milliseconds: 600)
      ..silent = true;
    await server.close();
    server =
        FakeSignalRServer(keepAliveTimeout: const Duration(milliseconds: 600))
          ..silent = true;
    await server.start();
    final c = builder().build()..createHubProxy('HubA');
    var slow = 0;
    c.onConnectionSlow(() => slow++);
    final reconnecting = Completer<Object?>();
    c.onReconnecting(reconnecting.complete);
    await c.start();
    expect(await reconnecting.future.timeout(const Duration(seconds: 5)),
        isA<SignalRTimeoutException>());
    expect(slow, greaterThanOrEqualTo(1));
    await c.stop();
  });

  test('3-5 independent connections with mixed transports', () async {
    final transports = [
      TransportType.webSockets,
      TransportType.serverSentEvents,
      TransportType.longPolling,
      TransportType.auto,
      TransportType.serverSentEvents,
    ];
    final manager = HubConnectionManager();
    final received = <String, List<Object?>>{};
    for (var i = 0; i < transports.length; i++) {
      final c = builder().withTransport(transports[i]).build();
      final name = 'c$i';
      c.createHubProxy('HubA').on('update', (args) {
        (received[name] ??= []).add(args[0]);
      });
      manager.add(name, c);
    }
    expect(() => manager.add('c0', builder().build()), throwsArgumentError);
    await manager.startAll();
    for (final c in manager.connections.values) {
      expect(c.state, ConnectionState.connected);
    }
    expect(manager['c2']!.transport, TransportType.longPolling);

    server.broadcast('HubA', 'update', ['x']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(received.keys, hasLength(5));

    await manager.stop('c1');
    expect(manager['c1']!.state, ConnectionState.disconnected);
    server.broadcast('HubA', 'update', ['y']);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(received['c1'], ['x']);
    expect(received['c0'], ['x', 'y']);
    expect(received['c2'], ['x', 'y']);
    expect(manager['c0']!.state, ConnectionState.connected);

    await manager.stopAll();
    expect(manager.remove('c0'), isNotNull);
    expect(manager.names, hasLength(4));
  });

  test('startAll reports failures and keeps the others', () async {
    final manager = HubConnectionManager()
      ..add('ok', builder().build())
      ..add(
        'bad',
        HubConnectionBuilder().withUrl('http://localhost:1').build(),
      );
    await expectLater(
      manager.startAll(),
      throwsA(isA<HubConnectionManagerException>()
          .having((e) => e.errors.keys, 'keys', ['bad'])),
    );
    expect(manager['ok']!.state, ConnectionState.connected);
    await manager.stopAll();
  });

  test('builder validation', () {
    expect(() => HubConnectionBuilder().build(), throwsArgumentError);
  });
}
