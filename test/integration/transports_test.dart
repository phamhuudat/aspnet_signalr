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

  HubConnection build(TransportType t) => HubConnectionBuilder()
      .withUrl(server.url.toString())
      .withTransport(t)
      .build();

  for (final type in [
    TransportType.webSockets,
    TransportType.serverSentEvents,
    TransportType.longPolling,
  ]) {
    group(type.name, () {
      test('start, invoke, receive, stop', () async {
        final connection = build(type);
        final hub = connection.createHubProxy('HubA');
        final received = Completer<List<dynamic>>();
        hub.on('update', (args) {
          if (!received.isCompleted) received.complete(args);
        });
        final states = <ConnectionState>[];
        connection.stateStream.listen(states.add);

        await connection.start();
        expect(connection.state, ConnectionState.connected);
        expect(connection.transport, type);
        expect(connection.connectionId, isNotNull);

        expect(await hub.invoke<int>('add', [2, 3]), 5);
        expect(await hub.invoke<String>('echo', ['hi']), 'hi');
        expect(
          await hub.invoke<Map<String, dynamic>>('echo', [
            {'a': 1},
          ]),
          {'a': 1},
        );
        await expectLater(
          hub.invoke<void>('fail', ['boom']),
          throwsA(
            isA<HubInvocationException>()
                .having((e) => e.message, 'message', 'boom')
                .having((e) => e.isHubException, 'hub', true)
                .having((e) => e.errorData, 'data', {'code': 42}),
          ),
        );

        await hub.invoke<void>('broadcast', ['tick']);
        expect(await received.future.timeout(const Duration(seconds: 5)), [
          'tick',
        ]);

        await connection.stop();
        expect(connection.state, ConnectionState.disconnected);
        expect(states, [
          ConnectionState.connecting,
          ConnectionState.connected,
          ConnectionState.disconnected,
        ]);
        expect(server.requestsTo('abort'), hasLength(1));
        expect(server.requestsTo('start').single.transport, type.queryValue);
      });

      test('reconnects with messageId and groupsToken after a drop', () async {
        final connection = build(type);
        final hub = connection.createHubProxy('HubA');
        final got = <Object?>[];
        hub.on('update', (args) => got.add(args[0]));
        final reconnected = Completer<bool>();
        connection.onReconnected(reconnected.complete);
        await connection.start();
        final id = connection.connectionId;
        await hub.invoke<void>('joinGroup', ['g1']);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        await server.dropAll();
        expect(
          await reconnected.future.timeout(const Duration(seconds: 10)),
          isFalse,
        );
        expect(connection.state, ConnectionState.connected);
        expect(connection.connectionId, id);
        final reconnect = server.requestsTo('reconnect').last;
        expect(reconnect.transport, type.queryValue);
        expect(reconnect.query['messageId'], isNotNull);
        expect(reconnect.query['groupsToken'], 'FAKE_GROUPS_g1');

        server.broadcast('HubA', 'update', ['after']);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(got, contains('after'));
        await connection.stop();
      });
    });
  }
}
