import '../../domain/exceptions/signalr_exception.dart';

/// Converts low level network errors into package exceptions.
///
/// Errors that mention the proxy (a failed `CONNECT` tunnel, a 407 response)
/// or connection errors while a proxy is configured become [ProxyException].
SignalRException mapNetworkError(
  Object error, {
  required bool proxyConfigured,
  required SignalRException Function(Object error) fallback,
}) {
  if (error is SignalRException) return error;
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('407') || lower.contains('proxy authentication')) {
    return ProxyException(
      'Proxy rejected the credentials',
      statusCode: 407,
      cause: error,
    );
  }
  if (lower.contains('proxy')) {
    return ProxyException('Proxy error', cause: error);
  }
  if (proxyConfigured &&
      (lower.contains('socketexception') ||
          lower.contains('connection refused') ||
          lower.contains('failed host lookup') ||
          lower.contains('connection reset'))) {
    return ProxyException('Cannot reach the proxy', cause: error);
  }
  return fallback(error);
}
