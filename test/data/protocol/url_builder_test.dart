import 'dart:math';

import 'package:aspnet_signalr/src/data/protocol/url_builder.dart';
import 'package:aspnet_signalr/src/domain/entities/connection_info.dart';
import 'package:aspnet_signalr/src/domain/entities/transport_type.dart';
import 'package:test/test.dart';

void main() {
  const info = ConnectionInfo(connectionId: 'id', connectionToken: 'a/b+c=');

  SignalRUrlBuilder builder(
    String url, {
    bool useDefaultPath = true,
    Map<String, String> query = const {},
  }) =>
      SignalRUrlBuilder(
        baseUrl: url,
        hubNames: ['HubA', 'hubB'],
        useDefaultPath: useDefaultPath,
        queryParameters: query,
        random: Random(1),
      );

  test('appends /signalr like \$.hubConnection', () {
    expect(builder('https://example.com').root.toString(),
        'https://example.com/signalr');
    expect(builder('https://example.com/app/').root.toString(),
        'https://example.com/app/signalr');
    expect(builder('https://example.com/a/signalr/hubs').root.path,
        '/a/signalr/hubs/signalr');
    expect(
      builder('https://example.com/app/signalr', useDefaultPath: false)
          .root
          .toString(),
      'https://example.com/app/signalr',
    );
  });

  test('negotiate has protocol and lower-case connectionData', () {
    final uri = builder('https://example.com').negotiate();
    expect(uri.path, '/signalr/negotiate');
    expect(uri.queryParameters['clientProtocol'], '1.5');
    expect(uri.queryParameters['connectionData'],
        '[{"name":"huba"},{"name":"hubb"}]');
    expect(uri.queryParameters.containsKey('_'), isTrue);
  });

  test('connect per transport', () {
    final b = builder('https://example.com');
    final ws = b.connect(TransportType.webSockets, info);
    expect(ws.scheme, 'wss');
    expect(ws.queryParameters['transport'], 'webSockets');
    expect(ws.queryParameters['connectionToken'], 'a/b+c=');
    expect(ws.queryParameters['tid'], isNotNull);
    expect(ws.toString(), contains('connectionToken=a%2Fb%2Bc%3D'));

    final sse = b.connect(TransportType.serverSentEvents, info);
    expect(sse.scheme, 'https');
    expect(sse.queryParameters['transport'], 'serverSentEvents');

    final lp = b.connect(TransportType.longPolling, info);
    expect(lp.queryParameters.containsKey('tid'), isFalse);
    expect(
        builder('http://example.com')
            .connect(TransportType.webSockets, info)
            .scheme,
        'ws');
  });

  test('reconnect and poll carry the cursor', () {
    final b = builder('https://example.com');
    final r = b.reconnect(TransportType.serverSentEvents, info,
        messageId: 'd-X,1|B,0', groupsToken: 'G');
    expect(r.path, '/signalr/reconnect');
    expect(r.queryParameters['messageId'], 'd-X,1|B,0');
    expect(r.queryParameters['groupsToken'], 'G');
    final p = b.poll(info, messageId: 'm');
    expect(p.path, '/signalr/poll');
    expect(p.queryParameters['transport'], 'longPolling');
    expect(p.queryParameters['messageId'], 'm');
    expect(p.queryParameters.containsKey('groupsToken'), isFalse);
  });

  test('start, send, abort and custom query', () {
    final b = builder('https://example.com?x=1', query: {'access_token': 't'});
    for (final uri in [
      b.start(TransportType.longPolling, info),
      b.send(TransportType.longPolling, info),
      b.abort(TransportType.longPolling, info),
    ]) {
      expect(uri.queryParameters['access_token'], 't');
      expect(uri.queryParameters['x'], '1');
      expect(uri.queryParameters['transport'], 'longPolling');
    }
    expect(b.start(TransportType.longPolling, info).path, '/signalr/start');
  });
}
