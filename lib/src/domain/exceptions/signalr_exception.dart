/// Base class of every error thrown by this package.
class SignalRException implements Exception {
  /// Creates an exception.
  const SignalRException(this.message, {this.cause});

  /// Human readable message.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' ($cause)' : ''}';
}

/// `/negotiate` or `/start` failed.
class NegotiateException extends SignalRException {
  /// Creates the exception.
  const NegotiateException(super.message, {this.statusCode, super.cause});

  /// HTTP status code, if a response was received.
  final int? statusCode;
}

/// The proxy could not be reached or rejected the credentials.
class ProxyException extends SignalRException {
  /// Creates the exception.
  const ProxyException(super.message, {this.statusCode, super.cause});

  /// HTTP status code from the proxy (407), if any.
  final int? statusCode;
}

/// No transport could connect, or the transport failed.
class TransportException extends SignalRException {
  /// Creates the exception.
  const TransportException(super.message, {super.cause});
}

/// The server method threw an error.
class HubInvocationException extends SignalRException {
  /// Creates the exception.
  const HubInvocationException(
    super.message, {
    this.errorData,
    this.isHubException = false,
  });

  /// Extra error data sent by the server (`D`).
  final Object? errorData;

  /// Whether the server threw a `HubException` on purpose.
  final bool isHubException;
}

/// An invocation or connect attempt timed out.
class SignalRTimeoutException extends SignalRException {
  /// Creates the exception.
  const SignalRTimeoutException(super.message);
}

/// Thrown by `HubConnectionManager.startAll` when some connections failed.
class HubConnectionManagerException extends SignalRException {
  /// Creates the exception.
  HubConnectionManagerException(this.errors)
      : super('Failed to start: ${errors.keys.join(', ')}');

  /// Error per connection name.
  final Map<String, Object> errors;
}
