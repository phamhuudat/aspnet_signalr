import 'package:http/http.dart' as http;

import '../../domain/exceptions/signalr_exception.dart';

/// Recognizes errors caused by the proxy for a request to `uri`.
///
/// Returns `null` when the error is not a proxy error (it comes from the
/// server, from a direct connection, or from the network after the proxy was
/// reached).
typedef ProxyErrorClassifier = ProxyException? Function(Object error, Uri? uri);

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
    this.classifyProxyError,
  });

  /// Client for HTTP requests (negotiate, start, send, poll, SSE).
  final http.Client client;

  /// `dart:io` `HttpClient` for WebSockets (`customClient`), if any.
  final Object? nativeClient;

  /// Whether [close] closes [client].
  final bool ownsClient;

  /// Set when a proxy is configured (on `dart:io` platforms).
  final ProxyErrorClassifier? classifyProxyError;

  /// Whether a proxy is configured.
  bool get proxyConfigured => classifyProxyError != null;

  /// Releases the clients if owned.
  void close() {
    if (ownsClient) client.close();
  }
}
