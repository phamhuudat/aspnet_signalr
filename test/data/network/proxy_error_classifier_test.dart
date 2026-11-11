@TestOn('vm')
library;

import 'dart:io';

import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:aspnet_signalr/src/data/network/proxy_error_classifier_io.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  const proxy = ProxyConfig(
    host: 'proxy.example.com',
    port: 8080,
    bypass: ['direct.example.com'],
  );
  final classify =
      IoProxyErrorClassifier((uri) => proxy.resolve(uri) ?? 'DIRECT');
  final viaProxy = Uri.parse('https://a.example.com/signalr/negotiate');
  final bypassed = Uri.parse('https://direct.example.com/signalr/negotiate');

  test('routing follows the PAC decision, ws/wss included', () {
    expect(classify.routesViaProxy(viaProxy), isTrue);
    expect(classify.routesViaProxy(bypassed), isFalse);
    expect(classify.routesViaProxy(Uri.parse('wss://a.example.com/x')), isTrue);
    expect(
      IoProxyErrorClassifier((_) => 'DIRECT; PROXY p:1')
          .routesViaProxy(viaProxy),
      isFalse,
    );
  });

  group('proxy errors', () {
    test('cannot reach the proxy', () {
      for (final message in [
        'Connection refused',
        "Failed host lookup: 'proxy.example.com'",
        'Network is unreachable',
      ]) {
        final e = classify(SocketException(message), viaProxy);
        expect(e, isA<ProxyException>(), reason: message);
        expect(e!.statusCode, isNull);
      }
    });

    test('tunnel refused with 407 (https/wss)', () {
      final e = classify(
        const HttpException(
            'Proxy failed to establish tunnel (407 Proxy Authentication Required)'),
        viaProxy,
      );
      expect(e?.statusCode, 407);
    });

    test('tunnel refused with another status', () {
      final e = classify(
        http.ClientException(
            'Proxy failed to establish tunnel (502 Bad Gateway)'),
        viaProxy,
      );
      expect(e?.statusCode, 502);
    });

    test('407 on a WebSocket upgrade, wrapped by web_socket_channel', () {
      final e = classify(
        WebSocketChannelException.from(
          const WebSocketException('not upgraded to websocket', 407),
        ),
        Uri.parse('ws://a.example.com/signalr/connect'),
      );
      expect(e?.statusCode, 407);
    });
  });

  group('not proxy errors', () {
    test('connection dropped after the proxy was reached', () {
      expect(
          classify(const SocketException('Connection reset by peer'), viaProxy),
          isNull);
      expect(
        classify(http.ClientException('Connection closed while receiving data'),
            viaProxy),
        isNull,
      );
    });

    test('direct (bypassed) requests are never proxy errors', () {
      expect(classify(const SocketException('Connection refused'), bypassed),
          isNull);
      expect(
        classify(
          const HttpException('Proxy failed to establish tunnel (407 x)'),
          bypassed,
        ),
        isNull,
      );
    });

    test('"407" or "proxy" in an unrelated message', () {
      expect(
        classify(
          http.ClientException('Connection closed, port = 54079'),
          viaProxy,
        ),
        isNull,
      );
      expect(
        classify(
          http.ClientException('Bad response'),
          Uri.parse('https://a.example.com/api/proxy/x'),
        ),
        isNull,
      );
    });

    test('WebSocket rejected by the server', () {
      expect(
        classify(
          WebSocketChannelException.from(
            const WebSocketException('not upgraded to websocket', 403),
          ),
          Uri.parse('wss://a.example.com/signalr/connect'),
        ),
        isNull,
      );
    });

    test('unknown uri', () {
      expect(
          classify(const SocketException('Connection refused'), null), isNull);
    });
  });
}
