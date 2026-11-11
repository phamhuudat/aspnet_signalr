import 'package:meta/meta.dart';

/// Connection parameters returned by `/negotiate`.
@immutable
class ConnectionInfo {
  /// Creates connection parameters.
  const ConnectionInfo({
    required this.connectionId,
    required this.connectionToken,
    this.url,
    this.keepAliveTimeout,
    this.disconnectTimeout = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 110),
    this.tryWebSockets = false,
    this.protocolVersion = '1.5',
    this.transportConnectTimeout = const Duration(seconds: 5),
    this.longPollDelay = Duration.zero,
  });

  /// App relative URL reported by the server.
  final String? url;

  /// Server assigned connection id.
  final String connectionId;

  /// Opaque token that must be sent with every request.
  final String connectionToken;

  /// `null` when the server has keep-alive disabled.
  final Duration? keepAliveTimeout;

  /// How long the server keeps the connection after the transport is lost.
  final Duration disconnectTimeout;

  /// How long the server holds a long poll request.
  final Duration connectionTimeout;

  /// Whether the server accepts WebSockets.
  final bool tryWebSockets;

  /// The protocol version of the server.
  final String protocolVersion;

  /// Time allowed for each transport to connect.
  final Duration transportConnectTimeout;

  /// Delay between two long poll requests.
  final Duration longPollDelay;
}
