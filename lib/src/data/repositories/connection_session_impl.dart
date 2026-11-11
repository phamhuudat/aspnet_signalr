import 'package:http/http.dart' as http_pkg;

import '../../core/logger.dart';
import '../../domain/entities/proxy_config.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/repositories/client_transport.dart';
import '../../domain/repositories/connection_session.dart';
import '../../domain/repositories/negotiation_repository.dart';
import '../datasources/signalr_http_datasource.dart';
import '../network/http_client_factory.dart';
import '../network/signalr_http_client.dart';
import '../protocol/url_builder.dart';
import '../transports/auto_transport.dart';
import '../transports/long_polling_transport.dart';
import '../transports/server_sent_events_transport.dart';
import '../transports/websocket_transport.dart';
import 'negotiation_repository_impl.dart';

/// Builds sessions over HTTP, SSE, long polling and WebSockets.
class DefaultConnectionSessionFactory implements ConnectionSessionFactory {
  /// Creates the factory.
  DefaultConnectionSessionFactory({
    required this.url,
    this.useDefaultPath = true,
    this.headers = const {},
    this.queryParameters = const {},
    this.proxy,
    this.httpClient,
    this.logger = const NoopLogger(),
  });

  final String url;
  final bool useDefaultPath;
  final Map<String, String> headers;
  final Map<String, String> queryParameters;
  final ProxyConfig? proxy;
  final http_pkg.Client? httpClient;
  final SignalRLogger logger;

  @override
  ConnectionSession create(List<String> hubNames) {
    final http = createSignalRHttpClient(
      proxy: proxy,
      userClient: httpClient,
      logger: logger,
    );
    final urls = SignalRUrlBuilder(
      baseUrl: url,
      hubNames: hubNames,
      useDefaultPath: useDefaultPath,
      queryParameters: queryParameters,
    );
    final dataSource = SignalRHttpDataSource(
      http: http,
      urls: urls,
      headers: headers,
      logger: logger,
    );
    return _Session(http, urls, dataSource, headers, logger);
  }
}

class _Session implements ConnectionSession {
  _Session(
      this._http, this._urls, this._dataSource, this._headers, this._logger)
      : negotiation = NegotiationRepositoryImpl(_dataSource);

  final SignalRHttpClient _http;
  final SignalRUrlBuilder _urls;
  final SignalRHttpDataSource _dataSource;
  final Map<String, String> _headers;
  final SignalRLogger _logger;

  @override
  final NegotiationRepository negotiation;

  @override
  ClientTransport createTransport(TransportType type) => switch (type) {
        TransportType.auto =>
          AutoTransport(factory: createTransport, logger: _logger),
        TransportType.webSockets => WebSocketTransport(
            urls: _urls,
            http: _http,
            headers: _headers,
            logger: _logger,
          ),
        TransportType.serverSentEvents => ServerSentEventsTransport(
            urls: _urls,
            dataSource: _dataSource,
            headers: _headers,
            logger: _logger,
          ),
        TransportType.longPolling => LongPollingTransport(
            urls: _urls,
            dataSource: _dataSource,
            logger: _logger,
          ),
      };

  @override
  void dispose() => _http.close();
}
