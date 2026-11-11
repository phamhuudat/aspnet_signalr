import 'package:meta/meta.dart';

/// Returns a PAC-style string for [uri]: `'DIRECT'` or `'PROXY host:port'`.
typedef ProxyResolver = String Function(Uri uri);

/// HTTP proxy settings for one connection.
///
/// The proxy is used for every request of the connection: negotiate, start,
/// send, Server-Sent Events, long polling and WebSockets (`CONNECT` for
/// secure URLs). Ignored on the Web.
@immutable
class ProxyConfig {
  /// A fixed proxy.
  const ProxyConfig({
    required String this.host,
    required int this.port,
    this.username,
    this.password,
    this.bypass = const [],
    this.allowBadCertificates = false,
  })  : resolver = null,
        environment = null,
        useEnvironment = false;

  /// Reads `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY` from [environment]
  /// (or from the process environment when omitted).
  const ProxyConfig.fromEnvironment({
    this.environment,
    this.allowBadCertificates = false,
  })  : host = null,
        port = null,
        username = null,
        password = null,
        bypass = const [],
        resolver = null,
        useEnvironment = true;

  /// Decides per request with [resolver].
  const ProxyConfig.custom(
    ProxyResolver this.resolver, {
    this.allowBadCertificates = false,
  })  : host = null,
        port = null,
        username = null,
        password = null,
        bypass = const [],
        environment = null,
        useEnvironment = false;

  /// Proxy host, for a fixed proxy.
  final String? host;

  /// Proxy port, for a fixed proxy.
  final int? port;

  /// Optional Basic proxy authentication user.
  final String? username;

  /// Optional Basic proxy authentication password.
  final String? password;

  /// Hosts that never use the proxy: `example.com`, `*.example.com`,
  /// `.example.com` or `localhost`.
  final List<String> bypass;

  /// Accept any TLS certificate. Only for debugging with an intercepting
  /// proxy. Never enable this in release builds.
  final bool allowBadCertificates;

  /// Custom resolver.
  final ProxyResolver? resolver;

  /// Environment used by [ProxyConfig.fromEnvironment].
  final Map<String, String>? environment;

  /// Whether this config reads the environment.
  final bool useEnvironment;

  /// Whether [requestHost] matches [bypass].
  bool shouldBypass(String requestHost) {
    final h = requestHost.toLowerCase();
    for (final raw in bypass) {
      final rule = raw.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule == '*') return true;
      if (rule.startsWith('*.')) {
        final suffix = rule.substring(1);
        if (h.endsWith(suffix) || h == rule.substring(2)) return true;
      } else if (rule.startsWith('.')) {
        if (h.endsWith(rule) || h == rule.substring(1)) return true;
      } else if (h == rule) {
        return true;
      }
    }
    return false;
  }

  /// The PAC-style decision for [uri] for a fixed proxy, or `null` when
  /// this config is environment based.
  String? resolve(Uri uri) {
    if (resolver != null) return resolver!(uri);
    if (useEnvironment) return null;
    if (shouldBypass(uri.host)) return 'DIRECT';
    final auth = username != null ? '${username!}:${password ?? ''}@' : '';
    return 'PROXY $auth$host:$port';
  }

  @override
  String toString() {
    if (resolver != null) return 'ProxyConfig.custom';
    if (useEnvironment) return 'ProxyConfig.fromEnvironment';
    return 'ProxyConfig($host:$port${username != null ? ', auth' : ''})';
  }
}
