import 'package:http/http.dart' as http_pkg;
import 'package:meta/meta.dart';

import '../application/default_reconnect_policy.dart';
import '../application/hub_connection_impl.dart';
import '../core/logger.dart';
import '../data/repositories/connection_session_impl.dart';
import '../domain/entities/proxy_config.dart';
import '../domain/entities/transport_type.dart';
import '../domain/policies/reconnect_policy.dart';
import '../domain/repositories/connection_session.dart';
import 'hub_connection.dart';

/// Configures and creates a [HubConnection].
class HubConnectionBuilder {
  String? _url;
  bool _useDefaultPath = true;
  Map<String, String> _headers = const {};
  Map<String, String> _query = const {};
  TransportType _transport = TransportType.auto;
  ProxyConfig? _proxy;
  ReconnectPolicy? _policy;
  SignalRLogger _logger = const NoopLogger();
  http_pkg.Client? _httpClient;
  Duration _invocationTimeout = const Duration(seconds: 30);
  ConnectionSessionFactory? _sessionFactory;

  /// Server URL. With [useDefaultPath] (default) `/signalr` is appended,
  /// like `$.hubConnection(url)` in the JavaScript client.
  ///
  /// [headers] are not supported by browsers for WebSockets and SSE; use
  /// [queryParameters] on the Web.
  HubConnectionBuilder withUrl(
    String url, {
    bool useDefaultPath = true,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
  }) {
    _url = url;
    _useDefaultPath = useDefaultPath;
    _headers = Map.unmodifiable(headers ?? const {});
    _query = Map.unmodifiable(queryParameters ?? const {});
    return this;
  }

  /// Transport, [TransportType.auto] by default.
  HubConnectionBuilder withTransport(TransportType transport) {
    _transport = transport;
    return this;
  }

  /// HTTP proxy for every request of this connection.
  HubConnectionBuilder withProxy(ProxyConfig proxy) {
    _proxy = proxy;
    return this;
  }

  /// Reconnects automatically, after each of [delays] (default 0s, 2s, 10s,
  /// 30s). Within the server `DisconnectTimeout` the same connection is
  /// resumed; after it a new connection is negotiated.
  HubConnectionBuilder withAutomaticReconnect({List<Duration>? delays}) {
    _policy = delays == null
        ? const DefaultReconnectPolicy()
        : DefaultReconnectPolicy(delays: List.unmodifiable(delays));
    return this;
  }

  /// Reconnects automatically using [policy].
  HubConnectionBuilder withReconnectPolicy(ReconnectPolicy policy) {
    _policy = policy;
    return this;
  }

  /// Logger, silent by default.
  HubConnectionBuilder withLogger(SignalRLogger logger) {
    _logger = logger;
    return this;
  }

  /// Custom `http.Client` for HTTP requests and SSE. Cannot be combined
  /// with [withProxy]. It is not closed by `stop()`.
  HubConnectionBuilder withHttpClient(http_pkg.Client client) {
    _httpClient = client;
    return this;
  }

  /// Default timeout of `HubProxy.invoke`, 30 seconds by default.
  HubConnectionBuilder withInvocationTimeout(Duration timeout) {
    _invocationTimeout = timeout;
    return this;
  }

  /// Replaces the network layer (for tests).
  @visibleForTesting
  HubConnectionBuilder withSessionFactory(ConnectionSessionFactory factory) {
    _sessionFactory = factory;
    return this;
  }

  /// Creates the connection.
  HubConnection build() {
    if (_proxy != null && _httpClient != null) {
      throw ArgumentError(
        'withProxy() and withHttpClient() cannot be combined: '
        'configure the proxy on your own client instead',
      );
    }
    final factory = _sessionFactory ??
        DefaultConnectionSessionFactory(
          url: _url ?? (throw ArgumentError('withUrl() is required')),
          useDefaultPath: _useDefaultPath,
          headers: _headers,
          queryParameters: _query,
          proxy: _proxy,
          httpClient: _httpClient,
          logger: _logger,
        );
    return HubConnectionImpl(
      sessionFactory: factory,
      transportType: _transport,
      reconnectPolicy: _policy,
      logger: _logger,
      invocationTimeout: _invocationTimeout,
    );
  }
}
