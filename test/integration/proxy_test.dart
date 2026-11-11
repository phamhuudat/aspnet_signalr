@TestOn('vm')
library;

import 'dart:io';

import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../tool/fake_proxy/fake_proxy.dart';
import '../../tool/fake_server/fake_signalr_server.dart';

void main() {
  late FakeSignalRServer server;
  late FakeProxy proxy;

  setUp(() async {
    server = FakeSignalRServer();
    await server.start();
  });

  tearDown(() async {
    await server.close();
    await proxy.close();
  });

  // The proxy is reached by IP so that "localhost" is not bypassed by
  // accident and the server URL keeps its own host name.
  ProxyConfig config({String? user, String? pass, List<String>? bypass}) =>
      ProxyConfig(
        host: '127.0.0.1',
        port: proxy.port,
        username: user,
        password: pass,
        bypass: bypass ?? const [],
      );

  for (final type in [
    TransportType.webSockets,
    TransportType.serverSentEvents,
    TransportType.longPolling,
  ]) {
    test('every request goes through the proxy (${type.name})', () async {
      proxy = FakeProxy();
      await proxy.start();
      final c = HubConnectionBuilder()
          .withUrl(server.url.toString())
          .withTransport(type)
          .withProxy(config())
          .build();
      final hub = c.createHubProxy('HubA');
      await c.start();
      expect(await hub.invoke<int>('add', [20, 22]), 42);
      await c.stop();
      final seen = proxy.requests.join('\n');
      for (final endpoint in ['negotiate', 'connect', 'start', 'abort']) {
        expect(seen, contains('/signalr/$endpoint'), reason: seen);
      }
      if (type != TransportType.webSockets) {
        expect(seen, contains('/signalr/send'));
      }
      if (type == TransportType.longPolling) {
        expect(seen, contains('/signalr/poll'));
      }
    });
  }

  test('proxy authentication', () async {
    proxy = FakeProxy(username: 'user', password: 'secret');
    await proxy.start();
    final ok = HubConnectionBuilder()
        .withUrl(server.url.toString())
        .withTransport(TransportType.serverSentEvents)
        .withProxy(config(user: 'user', pass: 'secret'))
        .build();
    await ok.start();
    await ok.stop();
    expect(proxy.requests, isNotEmpty);

    final bad = HubConnectionBuilder()
        .withUrl(server.url.toString())
        .withProxy(config(user: 'user', pass: 'wrong'))
        .build();
    await expectLater(
      bad.start(),
      throwsA(isA<ProxyException>().having((e) => e.statusCode, 'code', 407)),
    );
    expect(proxy.rejected, greaterThan(0));
  });

  test('password with special characters', () async {
    const pass = r'p@ss:w0rd!#%&$';
    proxy = FakeProxy(username: 'user', password: pass);
    await proxy.start();
    for (final type in [
      TransportType.webSockets,
      TransportType.serverSentEvents,
      TransportType.longPolling,
    ]) {
      final c = HubConnectionBuilder()
          .withUrl(server.url.toString())
          .withTransport(type)
          .withProxy(config(user: 'user', pass: pass))
          .build();
      final hub = c.createHubProxy('HubA');
      await c.start();
      expect(await hub.invoke<int>('add', [1, 2]), 3, reason: type.name);
      await c.stop();
    }
    expect(proxy.rejected, 0);
  });

  test('credentials dart:io cannot carry are rejected by build()', () {
    proxy = FakeProxy();
    for (final (user, pass) in [
      ('user', 'a;b'),
      ('dom:user', 'x'),
      ('', 'x'),
    ]) {
      expect(
        () => HubConnectionBuilder()
            .withUrl('http://example.com')
            .withProxy(ProxyConfig(
              host: 'proxy.example.com',
              port: 8080,
              username: user,
              password: pass,
            ))
            .build(),
        throwsA(isA<ArgumentError>()
            .having((e) => '${e.message}', 'message', isNot(contains('a;b')))),
        reason: '$user / $pass',
      );
    }
  });

  test('407 on the CONNECT tunnel (https) is a ProxyException', () async {
    proxy = FakeProxy(username: 'user', password: 'secret');
    await proxy.start();
    final c = HubConnectionBuilder()
        .withUrl('https://localhost:${server.url.port}')
        .withProxy(config(user: 'user', pass: 'wrong'))
        .build();
    await expectLater(
      c.start(),
      throwsA(isA<ProxyException>().having((e) => e.statusCode, 'code', 407)),
    );
  });

  test('server down behind a working proxy is not a ProxyException', () async {
    proxy = FakeProxy();
    await proxy.start();
    final closedPort = await _closedPort();
    final c = HubConnectionBuilder()
        .withUrl('http://localhost:$closedPort/api/proxy')
        .withProxy(config())
        .build();
    final error = await c.start().then<Object?>((_) => null, onError: (e) => e);
    expect(error, isA<SignalRException>());
    expect(error, isNot(isA<ProxyException>()));
    expect(proxy.requests.single, contains('/negotiate'));
  });

  test('a bypassed server that is down is not a ProxyException', () async {
    proxy = FakeProxy();
    await proxy.start();
    final closedPort = await _closedPort();
    final c = HubConnectionBuilder()
        .withUrl('http://localhost:$closedPort')
        .withProxy(config(bypass: ['localhost']))
        .build();
    final error = await c.start().then<Object?>((_) => null, onError: (e) => e);
    expect(error, isA<SignalRException>());
    expect(error, isNot(isA<ProxyException>()));
    expect(proxy.requests, isEmpty);
  });

  test('unreachable proxy is a ProxyException', () async {
    proxy = FakeProxy();
    await proxy.start();
    final port = proxy.port;
    await proxy.close();
    final c = HubConnectionBuilder()
        .withUrl(server.url.toString())
        .withProxy(ProxyConfig(host: '127.0.0.1', port: port))
        .build();
    await expectLater(c.start(), throwsA(isA<ProxyException>()));
  });

  test('bypassed hosts go direct', () async {
    proxy = FakeProxy();
    await proxy.start();
    final c = HubConnectionBuilder()
        .withUrl(server.url.toString())
        .withProxy(config(bypass: ['localhost']))
        .build();
    await c.start();
    await c.stop();
    expect(proxy.requests, isEmpty);
  });

  test('custom resolver decides per connection', () async {
    proxy = FakeProxy();
    await proxy.start();
    final viaProxy = HubConnectionBuilder()
        .withUrl(server.url.toString())
        .withProxy(ProxyConfig.custom((_) => 'PROXY 127.0.0.1:${proxy.port}'))
        .build();
    final direct =
        HubConnectionBuilder().withUrl(server.url.toString()).build();
    await viaProxy.start();
    final count = proxy.requests.length;
    await direct.start();
    expect(proxy.requests.length, count);
    await viaProxy.stop();
    await direct.stop();
  });

  test('withProxy and withHttpClient cannot be combined', () {
    proxy = FakeProxy();
    expect(
      () => HubConnectionBuilder()
          .withUrl('http://example.com')
          .withHttpClient(http.Client())
          .withProxy(const ProxyConfig(host: 'proxy.example.com', port: 8080))
          .build(),
      throwsArgumentError,
    );
  });
}

Future<int> _closedPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}
