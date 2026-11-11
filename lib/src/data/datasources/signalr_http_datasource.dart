import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http_pkg;

import '../../core/logger.dart';
import '../../domain/entities/connection_info.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/exceptions/signalr_exception.dart';
import '../dtos/json_helpers.dart';
import '../dtos/negotiate_response_dto.dart';
import '../network/error_mapper.dart';
import '../network/signalr_http_client.dart';
import '../protocol/url_builder.dart';

/// Plain HTTP requests of the protocol.
class SignalRHttpDataSource {
  /// Creates the data source.
  SignalRHttpDataSource({
    required this.http,
    required this.urls,
    this.headers = const {},
    this.logger = const NoopLogger(),
  });

  /// HTTP resources.
  final SignalRHttpClient http;

  /// URL builder.
  final SignalRUrlBuilder urls;

  /// Extra headers for every request.
  final Map<String, String> headers;

  /// Logger.
  final SignalRLogger logger;

  static const _form = 'application/x-www-form-urlencoded; charset=UTF-8';

  SignalRException _map(
    Object e,
    Uri uri,
    SignalRException Function(Object) fb,
  ) =>
      mapNetworkError(e, http: http, uri: uri, fallback: fb);

  Future<http_pkg.Response> _get(Uri uri) async {
    logger.log(LogLevel.debug, 'GET $uri');
    return http.client.get(uri, headers: headers);
  }

  Future<http_pkg.Response> _post(Uri uri, [String? data]) async {
    logger.log(LogLevel.debug, 'POST $uri');
    return http.client.post(
      uri,
      headers: {...headers, 'Content-Type': _form},
      body: data == null ? '' : 'data=${Uri.encodeQueryComponent(data)}',
    );
  }

  void _checkProxyStatus(http_pkg.Response res) {
    if (res.statusCode == 407) {
      throw const ProxyException(
        'Proxy rejected the credentials',
        statusCode: 407,
      );
    }
  }

  /// `GET /negotiate`.
  Future<NegotiateResponseDto> negotiate() async {
    final uri = urls.negotiate();
    final http_pkg.Response res;
    try {
      res = await _get(uri);
    } catch (e) {
      throw _map(
          e, uri, (e) => NegotiateException('Negotiate failed', cause: e));
    }
    _checkProxyStatus(res);
    if (res.statusCode != 200) {
      throw NegotiateException(
        'Negotiate failed with HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    final Object? json;
    try {
      json = jsonDecode(res.body);
    } on FormatException catch (e) {
      throw NegotiateException('Negotiate returned invalid JSON', cause: e);
    }
    final map = readMap(json);
    if (map == null || map['ConnectionToken'] == null) {
      throw const NegotiateException(
        'Negotiate response has no ConnectionToken. '
        'Is this an ASP.NET SignalR 2.x endpoint?',
      );
    }
    logger.log(LogLevel.trace, 'negotiate <- ${res.body}');
    return NegotiateResponseDto.fromJson(map);
  }

  /// `GET /start`.
  Future<void> start(TransportType transport, ConnectionInfo info) async {
    final uri = urls.start(transport, info);
    final http_pkg.Response res;
    try {
      res = await _get(uri);
    } catch (e) {
      throw _map(e, uri, (e) => NegotiateException('Start failed', cause: e));
    }
    _checkProxyStatus(res);
    if (res.statusCode != 200) {
      throw NegotiateException(
        'Start failed with HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    Object? response;
    try {
      response = readMap(jsonDecode(res.body))?['Response'];
    } on FormatException {
      response = null;
    }
    if (response != 'started') {
      throw NegotiateException('Unexpected start response: ${res.body}');
    }
  }

  /// `POST /abort`. Never throws.
  Future<void> abort(TransportType transport, ConnectionInfo info) async {
    try {
      await _post(urls.abort(transport, info))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      logger.log(LogLevel.debug, 'abort failed (ignored)', e);
    }
  }

  /// `POST /send` (SSE and long polling). Returns the response body, which
  /// holds the invocation result.
  Future<String> send(
    TransportType transport,
    ConnectionInfo info,
    String data,
  ) =>
      postForBody(urls.send(transport, info), data: data);

  /// POST and return the body; non 200 becomes [TransportException].
  Future<String> postForBody(Uri uri, {String? data}) async {
    final http_pkg.Response res;
    try {
      res = await _post(uri, data);
    } catch (e) {
      throw _map(e, uri, (e) => TransportException('POST failed', cause: e));
    }
    _checkProxyStatus(res);
    if (res.statusCode != 200) {
      throw TransportException('HTTP ${res.statusCode} from ${uri.path}');
    }
    return res.body;
  }
}
