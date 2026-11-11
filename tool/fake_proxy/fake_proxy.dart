/// A minimal forward HTTP proxy for tests (`dart:io` sockets).
///
/// - Absolute-form requests (`GET http://host/path HTTP/1.1`) are forwarded.
///   `Connection: close` is forced on non-upgrade requests so every request
///   opens a new connection and is recorded.
/// - `CONNECT host:port` opens a tunnel (used for `https`/`wss`).
/// - With [username]/[password], requests without the right
///   `Proxy-Authorization: Basic ...` get `407`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FakeProxy {
  FakeProxy({this.username, this.password});

  final String? username;
  final String? password;

  /// `METHOD target` of every request seen (after authentication).
  final requests = <String>[];

  /// Number of rejected (407) requests.
  int rejected = 0;

  ServerSocket? _server;
  final _sockets = <Socket>{};

  int get port => _server!.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
  }

  void _handle(Socket client) {
    _sockets.add(client);
    final buffer = BytesBuilder();
    late StreamSubscription<Uint8List> sub;
    var headDone = false;
    sub = client.listen(
      (data) async {
        if (headDone) return;
        buffer.add(data);
        final bytes = buffer.toBytes();
        final end = _indexOfHeadEnd(bytes);
        if (end < 0) return;
        headDone = true;
        sub.pause();
        final head = latin1.decode(bytes.sublist(0, end));
        final rest = bytes.sublist(end + 4);
        await _route(client, sub, head, rest);
      },
      onDone: () => _sockets.remove(client),
      onError: (Object _) => client.destroy(),
    );
  }

  static int _indexOfHeadEnd(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _route(
    Socket client,
    StreamSubscription<Uint8List> sub,
    String head,
    Uint8List rest,
  ) async {
    final lines = head.split('\r\n');
    final requestLine = lines.first.split(' ');
    final method = requestLine[0];
    final target = requestLine[1];
    final headers = <String, String>{};
    for (final l in lines.skip(1)) {
      final i = l.indexOf(':');
      if (i > 0) {
        headers[l.substring(0, i).toLowerCase()] = l.substring(i + 1).trim();
      }
    }
    if (username != null) {
      final expected =
          'Basic ${base64.encode(utf8.encode('$username:${password ?? ''}'))}';
      if (headers['proxy-authorization'] != expected) {
        rejected++;
        client
            .add(latin1.encode('HTTP/1.1 407 Proxy Authentication Required\r\n'
                'Proxy-Authenticate: Basic realm="fake"\r\n'
                'Content-Length: 0\r\nConnection: close\r\n\r\n'));
        await client.flush();
        client.destroy();
        return;
      }
    }
    requests.add('$method $target');

    final String host;
    final int port;
    if (method == 'CONNECT') {
      final hp = target.split(':');
      host = hp[0];
      port = int.parse(hp[1]);
    } else {
      final uri = Uri.parse(target);
      host = uri.host;
      port = uri.port;
    }
    final Socket upstream;
    try {
      upstream = await Socket.connect(host, port);
    } catch (_) {
      client.add(latin1.encode(
          'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
      await client.flush();
      client.destroy();
      return;
    }
    _sockets.add(upstream);
    if (method == 'CONNECT') {
      client.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
    } else {
      final upgrade = headers['upgrade'] != null;
      final out = StringBuffer('${lines.first}\r\n');
      for (final l in lines.skip(1)) {
        final name = l.split(':').first.toLowerCase();
        if (name.startsWith('proxy-')) continue;
        if (!upgrade && name == 'connection') continue;
        out.write('$l\r\n');
      }
      if (!upgrade) out.write('Connection: close\r\n');
      out.write('\r\n');
      upstream.add(latin1.encode(out.toString()));
    }
    if (rest.isNotEmpty) upstream.add(rest);
    upstream.listen(
      client.add,
      onDone: () => client.destroy(),
      onError: (Object _) => client.destroy(),
    );
    sub.onData(upstream.add);
    sub.onDone(() => upstream.destroy());
    sub.resume();
  }
}
