import 'package:meta/meta.dart';

/// A client to server hub method call.
@immutable
class HubInvocation {
  /// Creates an invocation.
  const HubInvocation({
    required this.hub,
    required this.method,
    required this.id,
    this.args = const [],
    this.state,
  });

  /// Hub name.
  final String hub;

  /// Server method name.
  final String method;

  /// Arguments, must be JSON encodable.
  final List<Object?> args;

  /// Callback id used to match the result.
  final String id;

  /// Optional hub state.
  final Map<String, dynamic>? state;
}
