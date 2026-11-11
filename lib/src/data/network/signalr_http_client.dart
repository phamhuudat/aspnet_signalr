import 'package:http/http.dart' as http;

/// HTTP resources of one connection session.
///
/// On `dart:io` platforms [nativeClient] is the `HttpClient` configured with
/// the proxy, shared by HTTP requests, SSE and WebSockets.
class SignalRHttpClient {
  /// Creates the bundle.
  SignalRHttpClient({
    required this.client,
    this.nativeClient,
    this.ownsClient = true,
    this.proxyConfigured = false,
  });

  /// Client for HTTP requests (negotiate, start, send, poll, SSE).
  final http.Client client;

  /// `dart:io` `HttpClient` for WebSockets (`customClient`), if any.
  final Object? nativeClient;

  /// Whether [close] closes [client].
  final bool ownsClient;

  /// Whether a proxy is configured, used to map errors.
  final bool proxyConfigured;

  /// Releases the clients if owned.
  void close() {
    if (ownsClient) client.close();
  }
}
