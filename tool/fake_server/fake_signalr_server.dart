/// A small ASP.NET SignalR 2.x server used by the integration tests and the
/// example. It speaks protocol 1.5 over WebSockets, Server-Sent Events and
/// long polling.
///
/// Hub methods (any hub, case insensitive):
/// - `echo(x)` returns `x`
/// - `add(a, b)` returns `a + b`
/// - `fail(message)` throws a hub error with `D: {"code": 42}`
/// - `joinGroup(name)` joins a group and updates the groups token
/// - `broadcast(x)` sends `update(x)` to every client, returns `null`
/// - `never()` never answers
/// - `counter()` increments and returns the hub state field `count`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One recorded request.
class RecordedRequest {
  RecordedRequest(this.method, this.endpoint, this.query, this.headers);

  final String method;
  final String endpoint;
  final Map<String, String> query;
  final Map<String, String> headers;

  String? get transport => query['transport'];

  @override
  String toString() => '$method $endpoint ${transport ?? ''}';
}

/// Server side state of one SignalR connection.
class FakeConnection {
  FakeConnection(this.connectionId, this.token, this.hubs);

  final String connectionId;
  final String token;
  final List<String> hubs;
  final groups = <String>{};
  int cursor = 0;
  String? transport;
  StreamController<List<int>>? sse;
  WebSocketChannel? socket;
  Completer<void>? pollWaiter;
  final pending = <Map<String, dynamic>>[];

  String get messageId => 'd-FAKE-B,$cursor|C,0|D,1';
  String? get groupsToken =>
      groups.isEmpty ? null : 'FAKE_GROUPS_${groups.join('_')}';
}

/// The fake server.
class FakeSignalRServer {
  FakeSignalRServer({
    this.tryWebSockets = true,
    this.keepAliveTimeout = const Duration(seconds: 20),
    this.disconnectTimeout = const Duration(seconds: 30),
    this.transportConnectTimeout = const Duration(seconds: 5),
    this.pollTimeout = const Duration(seconds: 2),
    this.basePath = '/signalr',
  });

  bool tryWebSockets;
  Duration? keepAliveTimeout;
  Duration disconnectTimeout;
  Duration transportConnectTimeout;
  Duration pollTimeout;
  final String basePath;

  /// Reject SSE connects with 404 (forces the long polling fallback).
  bool sseEnabled = true;

  /// Reject WebSocket connects with 404.
  bool webSocketsEnabled = true;

  /// Do not send `S: 1` on connect (simulates a stuck transport).
  bool sendInit = true;

  /// Stop sending keep-alives.
  bool silent = false;

  /// Number of next negotiate calls that fail with HTTP 500.
  int failNegotiate = 0;

  /// Reject reconnect requests with HTTP 500.
  bool rejectReconnect = false;

  final requests = <RecordedRequest>[];
  final connections = <String, FakeConnection>{};
  final invocations = <Map<String, dynamic>>[];

  HttpServer? _server;
  Timer? _keepAliveTimer;
  int _ids = 0;

  Uri get url => Uri.parse('http://localhost:${_server!.port}');

  /// Requests to [endpoint] (e.g. `negotiate`, `reconnect`).
  List<RecordedRequest> requestsTo(String endpoint) =>
      requests.where((r) => r.endpoint == endpoint).toList();

  Future<void> start({int port = 0}) async {
    _server = await shelf_io.serve(_handle, 'localhost', port);
    final ka = keepAliveTimeout;
    if (ka != null) {
      _keepAliveTimer = Timer.periodic(ka ~/ 2, (_) {
        if (silent) return;
        for (final c in connections.values) {
          _push(c, const <String, dynamic>{}, keepAlive: true);
        }
      });
    }
  }

  Future<void> close() async {
    _keepAliveTimer?.cancel();
    await dropAll();
    await _server?.close(force: true);
  }

  // ------------------------------------------------------------ controls

  /// Sends `hub.method(args)` to every connection.
  void broadcast(String hub, String method, List<Object?> args) {
    for (final c in connections.values) {
      send(c, hub, method, args);
    }
  }

  /// Sends `hub.method(args)` to [c].
  void send(FakeConnection c, String hub, String method, List<Object?> args) {
    c.cursor++;
    _push(c, {
      'C': c.messageId,
      'M': [
        {'H': hub, 'M': method, 'A': args},
      ],
    });
  }

  /// Sends a raw persistent response to every connection.
  void pushRaw(Map<String, dynamic> frame) {
    for (final c in connections.values) {
      _push(c, frame);
    }
  }

  /// Abruptly closes every transport (connections stay known).
  Future<void> dropAll() async {
    for (final c in connections.values) {
      await _dropTransport(c);
    }
  }

  Future<void> _dropTransport(FakeConnection c) async {
    final sse = c.sse;
    c.sse = null;
    await sse?.close();
    final ws = c.socket;
    c.socket = null;
    await ws?.sink.close(4000, "dropped");
    final poll = c.pollWaiter;
    c.pollWaiter = null;
    if (poll != null && !poll.isCompleted) poll.completeError('dropped');
  }

  // ------------------------------------------------------------- routing

  Future<Response> _handle(Request request) async {
    final path = '/${request.url.path}';
    if (!path.startsWith('$basePath/')) return Response.notFound('no route');
    final endpoint = path.substring(basePath.length + 1);
    final query = request.url.queryParameters;
    requests.add(
      RecordedRequest(request.method, endpoint, query, request.headers),
    );
    switch (endpoint) {
      case 'negotiate':
        return _negotiate(query);
      case 'connect':
      case 'reconnect':
        return _connect(request, query, reconnect: endpoint == 'reconnect');
      case 'start':
        return _withConnection(query, (_) {
          return Response.ok(
            jsonEncode({'Response': 'started'}),
            headers: {'content-type': 'application/json'},
          );
        });
      case 'send':
        final body = await request.readAsString();
        final data = Uri.splitQueryString(body)['data'] ?? '';
        return _withConnection(query, (c) async {
          final result = await _invoke(c, data);
          return Response.ok(result == null ? '' : jsonEncode(result));
        });
      case 'poll':
        return _withConnection(query, (c) => _poll(c, query));
      case 'abort':
        return _withConnection(query, (c) async {
          connections.remove(c.token);
          await _dropTransport(c);
          return Response.ok('');
        });
    }
    return Response.notFound('unknown endpoint $endpoint');
  }

  Future<Response> _withConnection(
    Map<String, String> query,
    FutureOr<Response> Function(FakeConnection c) body,
  ) async {
    final c = connections[query['connectionToken']];
    if (c == null) return Response.forbidden('unknown connection token');
    return body(c);
  }

  Response _negotiate(Map<String, String> query) {
    if (failNegotiate > 0) {
      failNegotiate--;
      return Response.internalServerError(body: 'negotiate failure');
    }
    final hubs = <String>[];
    final data = query['connectionData'];
    if (data != null) {
      for (final h in jsonDecode(data) as List) {
        hubs.add((h as Map)['name'] as String);
      }
    }
    _ids++;
    final id = '00000000-0000-0000-0000-${_ids.toString().padLeft(12, '0')}';
    final token = 'FAKE_TOKEN_$_ids/+=';
    connections[token] = FakeConnection(id, token, hubs);
    double? s(Duration? d) => d == null ? null : d.inMilliseconds / 1000;
    return Response.ok(
      jsonEncode({
        'Url': basePath,
        'ConnectionToken': token,
        'ConnectionId': id,
        'KeepAliveTimeout': s(keepAliveTimeout),
        'DisconnectTimeout': s(disconnectTimeout),
        'ConnectionTimeout': s(pollTimeout),
        'TryWebSockets': tryWebSockets,
        'ProtocolVersion': '1.5',
        'TransportConnectTimeout': s(transportConnectTimeout),
        'LongPollDelay': 0.0,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _connect(
    Request request,
    Map<String, String> query, {
    required bool reconnect,
  }) async {
    final c = connections[query['connectionToken']];
    if (c == null) return Response.forbidden('unknown connection token');
    if (reconnect && rejectReconnect) {
      return Response.internalServerError(body: 'reconnect rejected');
    }
    final transport = query['transport'];
    await _dropTransport(c);
    c.transport = transport;
    final init = <String, dynamic>{
      'C': c.messageId,
      if (!reconnect) 'S': 1,
      if (c.groupsToken != null) 'G': c.groupsToken,
      'M': <Object?>[],
    };
    switch (transport) {
      case 'webSockets':
        if (!webSocketsEnabled || !tryWebSockets) {
          return Response.notFound('websockets disabled');
        }
        return webSocketHandler((WebSocketChannel ws, String? _) {
          c.socket = ws;
          if (!reconnect && sendInit) ws.sink.add(jsonEncode(init));
          _flush(c);
          ws.stream.listen(
            (data) async {
              final result = await _invoke(c, data as String);
              if (result != null && c.socket == ws) {
                ws.sink.add(jsonEncode(result));
              }
            },
            onDone: () {
              if (c.socket == ws) c.socket = null;
            },
          );
        })(request);
      case 'serverSentEvents':
        if (!sseEnabled) return Response.notFound('sse disabled');
        late final StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          onCancel: () {
            if (c.sse == controller) c.sse = null;
          },
        );
        c.sse = controller;
        controller.add(utf8.encode('data: initialized\n\n'));
        if (!reconnect && sendInit) {
          controller.add(utf8.encode('data: ${jsonEncode(init)}\n\n'));
        }
        _flush(c);
        return Response.ok(
          controller.stream,
          headers: {
            'content-type': 'text/event-stream',
            'cache-control': 'no-cache',
          },
          context: {'shelf.io.buffer_output': false},
        );
      case 'longPolling':
        if (reconnect) return _poll(c, query);
        return Response.ok(sendInit ? jsonEncode(init) : '{}');
    }
    return Response.badRequest(body: 'unknown transport $transport');
  }

  Future<Response> _poll(FakeConnection c, Map<String, String> query) async {
    if (c.pending.isEmpty) {
      final waiter = c.pollWaiter = Completer<void>();
      try {
        await waiter.future.timeout(pollTimeout, onTimeout: () {});
      } catch (_) {
        return Response.internalServerError(body: 'dropped');
      }
    }
    if (c.pollWaiter != null && c.pollWaiter!.isCompleted) c.pollWaiter = null;
    final messages = <Object?>[];
    for (final p in c.pending) {
      messages.addAll((p['M'] as List?) ?? const []);
    }
    c.pending.clear();
    // Real servers pad long poll responses with whitespace.
    return Response.ok(
      '   ${jsonEncode({
            'C': c.messageId,
            if (c.groupsToken != null) 'G': c.groupsToken,
            'M': messages,
          })}',
    );
  }

  void _push(
    FakeConnection c,
    Map<String, dynamic> frame, {
    bool keepAlive = false,
  }) {
    final text = jsonEncode(frame);
    if (c.socket != null) {
      c.socket!.sink.add(text);
    } else if (c.sse != null) {
      c.sse!.add(utf8.encode('data: $text\n\n'));
    } else if (c.transport == 'longPolling' && !keepAlive) {
      c.pending.add(frame);
      final w = c.pollWaiter;
      if (w != null && !w.isCompleted) w.complete();
    } else if (!keepAlive) {
      c.pending.add(frame);
    }
  }

  void _flush(FakeConnection c) {
    if (c.transport == 'longPolling') return;
    final pending = List.of(c.pending);
    c.pending.clear();
    for (final p in pending) {
      _push(c, p);
    }
  }

  // ------------------------------------------------------------- hubs

  Future<Map<String, dynamic>?> _invoke(FakeConnection c, String data) async {
    final inv = jsonDecode(data) as Map<String, dynamic>;
    invocations.add(inv);
    final id = '${inv['I']}';
    final args = (inv['A'] as List?) ?? const [];
    final method = '${inv['M']}'.toLowerCase();
    switch (method) {
      case 'echo':
        return {'I': id, 'R': args.isEmpty ? null : args[0]};
      case 'add':
        return {'I': id, 'R': (args[0] as num) + (args[1] as num)};
      case 'fail':
        return {
          'I': id,
          'E': args.isEmpty ? 'failure' : '${args[0]}',
          'H': true,
          'D': {'code': 42},
        };
      case 'joingroup':
        c.groups.add('${args[0]}');
        c.cursor++;
        _push(c, {'C': c.messageId, 'G': c.groupsToken, 'M': <Object?>[]});
        return {'I': id};
      case 'broadcast':
        broadcast('${inv['H']}', 'update', args);
        return {'I': id};
      case 'counter':
        final state = Map<String, dynamic>.from((inv['S'] as Map?) ?? {});
        final count = ((state['count'] as num?) ?? 0) + 1;
        return {
          'I': id,
          'R': count,
          'S': {'count': count},
        };
      case 'never':
        return null;
    }
    return {
      'I': id,
      'E': "'${inv['M']}' method could not be resolved.",
    };
  }
}
