import 'package:meta/meta.dart';

/// A hub method call pushed by the server to the client.
@immutable
class HubMessage {
  /// Creates a hub message.
  const HubMessage({
    required this.hub,
    required this.method,
    this.args = const [],
    this.state,
  });

  /// Hub name, as sent by the server.
  final String hub;

  /// Client method name.
  final String method;

  /// Already JSON decoded arguments.
  final List<dynamic> args;

  /// Optional hub state sent by the server.
  final Map<String, dynamic>? state;
}
