import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/exceptions/signalr_exception.dart';

/// Recognizes proxy errors on `dart:io` platforms.
///
/// - `CONNECT` tunnel refused by the proxy (`https`/`wss`): `dart:io` throws
///   `HttpException('Proxy failed to establish tunnel (<status> ...)')`.
/// - `407` on a WebSocket upgrade through the proxy (`ws`).
/// - The proxy cannot be reached: a connect-time `SocketException` for a
///   request that is routed through the proxy. Through a proxy the client
///   only ever opens sockets to the proxy, so such an error is about the
///   proxy. Errors after the connection was established (reset, closed) are
///   not proxy errors: the server may have dropped the connection.
///
/// (`407` on plain HTTP requests is a normal response and is checked by the
/// callers.)
class IoProxyErrorClassifier {
  /// Creates the classifier; [findProxy] is the PAC decision used by the
  /// session `HttpClient`.
  IoProxyErrorClassifier(this.findProxy);

  /// The PAC-style decision for an `http`/`https` URI.
  final String Function(Uri uri) findProxy;

  static final _tunnelStatus =
      RegExp(r'Proxy failed to establish tunnel \((\d{3})');

  static const _connectFailures = [
    'connection refused',
    'failed host lookup',
    'network is unreachable',
    'no route to host',
    'host is down',
    'connection timed out',
    'operation timed out',
  ];

  /// Whether a request to [uri] goes through the proxy.
  bool routesViaProxy(Uri uri) {
    final httpUri = switch (uri.scheme) {
      'ws' => uri.replace(scheme: 'http'),
      'wss' => uri.replace(scheme: 'https'),
      _ => uri,
    };
    final String decision;
    try {
      decision = findProxy(httpUri);
    } catch (_) {
      return false;
    }
    for (final entry in decision.split(';')) {
      final e = entry.trim();
      if (e.isEmpty) continue;
      return e.startsWith('PROXY ');
    }
    return false;
  }

  /// Returns a [ProxyException] for proxy errors, otherwise `null`.
  ProxyException? call(Object error, Uri? uri) {
    var e = error;
    if (e is WebSocketChannelException && e.inner != null) e = e.inner!;
    if (uri == null || !routesViaProxy(uri)) return null;

    if (e is SocketException) {
      final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
      if (_connectFailures.any(text.contains)) {
        return ProxyException('Cannot reach the proxy', cause: error);
      }
      return null;
    }

    final String? message = switch (e) {
      HttpException(:final message) => message,
      http.ClientException(:final message) => message,
      _ => null,
    };
    if (message != null) {
      final match = _tunnelStatus.firstMatch(message);
      if (match == null) return null;
      final status = int.parse(match.group(1)!);
      return status == 407
          ? ProxyException(
              'Proxy rejected the credentials',
              statusCode: 407,
              cause: error,
            )
          : ProxyException(
              'Proxy failed to open a tunnel to the server (HTTP $status)',
              statusCode: status,
              cause: error,
            );
    }

    if (e is WebSocketException && e.httpStatusCode == 407) {
      return ProxyException(
        'Proxy rejected the credentials',
        statusCode: 407,
        cause: error,
      );
    }
    return null;
  }
}
