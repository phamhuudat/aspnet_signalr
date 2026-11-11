import '../../domain/exceptions/signalr_exception.dart';
import 'signalr_http_client.dart';

/// Converts low level network errors into package exceptions.
///
/// An error becomes a [ProxyException] only when [SignalRHttpClient.classifyProxyError]
/// recognizes it as caused by the proxy for the request to [uri]. The
/// decision is based on the error type and on whether that request is
/// routed through the proxy, never on words found in the message, so errors
/// of the server (or of a URL that happens to contain "proxy") keep their
/// own type and `auto` can still fall back to the next transport.
SignalRException mapNetworkError(
  Object error, {
  required SignalRHttpClient http,
  Uri? uri,
  required SignalRException Function(Object error) fallback,
}) {
  if (error is SignalRException) return error;
  return http.classifyProxyError?.call(error, uri) ?? fallback(error);
}
