import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http_pkg;

import '../../../domain/exceptions/signalr_exception.dart';
import '../../network/signalr_http_client.dart';
import 'sse_connection.dart';
import 'sse_parser.dart';

/// Opens an SSE stream with a streamed `GET` (uses the proxied client).
Future<SseConnection> openSseConnection(
  Uri uri, {
  required SignalRHttpClient http,
  Map<String, String> headers = const {},
}) async {
  final request = http_pkg.Request('GET', uri)
    ..headers.addAll(headers)
    ..headers['Accept'] = 'text/event-stream'
    ..headers['Cache-Control'] = 'no-cache';
  final response = await http.client.send(request);
  if (response.statusCode == 407) {
    await response.stream.drain<void>().catchError((_) {});
    throw const ProxyException(
      'Proxy rejected the credentials',
      statusCode: 407,
    );
  }
  if (response.statusCode != 200) {
    await response.stream.drain<void>().catchError((_) {});
    throw TransportException('SSE connect failed with HTTP '
        '${response.statusCode}');
  }
  return _IoSseConnection(response.stream);
}

class _IoSseConnection implements SseConnection {
  _IoSseConnection(Stream<List<int>> body) {
    _sub = body
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .transform(const SseEventTransformer())
        .listen(
          _controller.add,
          onError: _controller.addError,
          onDone: _controller.close,
          cancelOnError: true,
        );
  }

  final _controller = StreamController<String>();
  late final StreamSubscription<String> _sub;

  @override
  Stream<String> get events => _controller.stream;

  @override
  Future<void> close() async {
    // Cancelling the body subscription closes the socket.
    unawaited(_sub.cancel().catchError((_) {}));
    if (!_controller.isClosed) await _controller.close();
  }
}
