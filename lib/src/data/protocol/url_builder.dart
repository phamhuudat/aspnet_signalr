import 'dart:convert';
import 'dart:math';

import '../../domain/entities/connection_info.dart';
import '../../domain/entities/transport_type.dart';

/// Builds every URL of the ASP.NET SignalR 2.x protocol (version 1.5).
class SignalRUrlBuilder {
  /// Creates a builder.
  ///
  /// With [useDefaultPath] `/signalr` is appended to [baseUrl], the same as
  /// `$.hubConnection(url)` of the JavaScript client.
  SignalRUrlBuilder({
    required String baseUrl,
    required List<String> hubNames,
    bool useDefaultPath = true,
    Map<String, String> queryParameters = const {},
    Random? random,
  })  : _root = _normalize(baseUrl, useDefaultPath),
        _connectionData = hubNames.isEmpty
            ? null
            : jsonEncode([
                for (final h in hubNames) {'name': h.toLowerCase()},
              ]),
        _query = Map.unmodifiable(queryParameters),
        _random = random ?? Random();

  /// Protocol version sent as `clientProtocol`.
  static const clientProtocol = '1.5';

  final Uri _root;
  final String? _connectionData;
  final Map<String, String> _query;
  final Random _random;

  /// The endpoint root, e.g. `https://host/app/signalr`.
  Uri get root => _root;

  /// Value of the `connectionData` parameter.
  String? get connectionData => _connectionData;

  static Uri _normalize(String baseUrl, bool useDefaultPath) {
    final uri = Uri.parse(baseUrl);
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (useDefaultPath) path = '$path/signalr';
    return uri.replace(path: path, query: uri.query.isEmpty ? null : uri.query);
  }

  Uri _build(String endpoint, Map<String, String> params) {
    final q = <String, String>{
      ..._root.queryParameters,
      ...params,
      ..._query,
    };
    return _root.replace(path: '${_root.path}/$endpoint', queryParameters: q);
  }

  Map<String, String> _common(TransportType transport, ConnectionInfo info) => {
        'transport': transport.queryValue!,
        'clientProtocol': clientProtocol,
        'connectionToken': info.connectionToken,
        if (_connectionData != null) 'connectionData': _connectionData,
      };

  Map<String, String> _cursor(String? messageId, String? groupsToken) => {
        if (messageId != null) 'messageId': messageId,
        if (groupsToken != null) 'groupsToken': groupsToken,
      };

  /// `GET /negotiate`.
  Uri negotiate() => _build('negotiate', {
        'clientProtocol': clientProtocol,
        if (_connectionData != null) 'connectionData': _connectionData,
        '_': '${DateTime.now().millisecondsSinceEpoch}',
      });

  /// `/connect`. WebSocket URLs use the `ws`/`wss` scheme.
  Uri connect(TransportType transport, ConnectionInfo info) => _ws(
        transport,
        _build('connect', {
          ..._common(transport, info),
          if (transport != TransportType.longPolling)
            'tid': '${_random.nextInt(11)}',
        }),
      );

  /// `/reconnect` with the message cursor.
  Uri reconnect(
    TransportType transport,
    ConnectionInfo info, {
    String? messageId,
    String? groupsToken,
  }) =>
      _ws(
        transport,
        _build('reconnect', {
          ..._common(transport, info),
          ..._cursor(messageId, groupsToken),
        }),
      );

  /// `POST /poll` (long polling).
  Uri poll(ConnectionInfo info, {String? messageId, String? groupsToken}) =>
      _build('poll', {
        ..._common(TransportType.longPolling, info),
        ..._cursor(messageId, groupsToken),
      });

  /// `GET /start`.
  Uri start(TransportType transport, ConnectionInfo info) =>
      _build('start', _common(transport, info));

  /// `POST /send`.
  Uri send(TransportType transport, ConnectionInfo info) =>
      _build('send', _common(transport, info));

  /// `POST /abort`.
  Uri abort(TransportType transport, ConnectionInfo info) =>
      _build('abort', _common(transport, info));

  Uri _ws(TransportType transport, Uri uri) {
    if (transport != TransportType.webSockets) return uri;
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
  }
}
