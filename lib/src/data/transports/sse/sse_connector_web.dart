import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../../domain/exceptions/signalr_exception.dart';
import '../../network/signalr_http_client.dart';
import 'sse_connection.dart';

/// Opens an SSE stream with the browser `EventSource`.
///
/// Custom headers are not supported by browsers; use query parameters.
Future<SseConnection> openSseConnection(
  Uri uri, {
  required SignalRHttpClient http,
  Map<String, String> headers = const {},
}) {
  final opened = Completer<SseConnection>();
  final source = web.EventSource(
    uri.toString(),
    web.EventSourceInit(withCredentials: true),
  );
  final connection = _WebSseConnection(source);
  source.onopen = ((web.Event _) {
    if (!opened.isCompleted) opened.complete(connection);
  }).toJS;
  source.onmessage = ((web.MessageEvent e) {
    connection._add('${e.data.dartify()}');
  }).toJS;
  source.onerror = ((web.Event _) {
    // Prevent the browser's own retry: SignalR drives reconnects.
    source.close();
    if (!opened.isCompleted) {
      opened.completeError(const TransportException('EventSource failed'));
    } else {
      connection._fail(const TransportException('EventSource closed'));
    }
  }).toJS;
  return opened.future;
}

class _WebSseConnection implements SseConnection {
  _WebSseConnection(this._source);

  final web.EventSource _source;
  final _controller = StreamController<String>();

  void _add(String data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  void _fail(Object error) {
    if (_controller.isClosed) return;
    _controller.addError(error);
    _controller.close();
  }

  @override
  Stream<String> get events => _controller.stream;

  @override
  Future<void> close() async {
    _source.close();
    if (!_controller.isClosed) await _controller.close();
  }
}
