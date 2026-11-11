import 'package:meta/meta.dart';

import 'hub_message.dart';

/// Anything the server can send on a transport.
@immutable
sealed class ServerMessage {
  const ServerMessage();
}

/// An empty `{}` keep-alive frame.
final class KeepAliveMessage extends ServerMessage {
  /// Creates a keep-alive.
  const KeepAliveMessage();
}

/// A persistent response: `{C, M, S, T, D, G, L}`.
final class PersistentResponse extends ServerMessage {
  /// Creates a persistent response.
  const PersistentResponse({
    this.messageId,
    this.messages = const [],
    this.rawMessages = const [],
    this.initialized = false,
    this.shouldReconnect = false,
    this.disconnect = false,
    this.groupsToken,
    this.longPollDelay,
  });

  /// Message cursor (`C`).
  final String? messageId;

  /// Hub messages in `M`.
  final List<HubMessage> messages;

  /// Items of `M` that are not hub messages (persistent connection API).
  final List<Object?> rawMessages;

  /// `S: 1`: the transport is initialized.
  final bool initialized;

  /// `T: 1`: the server asks the client to reconnect.
  final bool shouldReconnect;

  /// `D: 1`: the server asks the client to disconnect.
  final bool disconnect;

  /// Groups token (`G`).
  final String? groupsToken;

  /// Long poll delay (`L`).
  final Duration? longPollDelay;
}

/// The result of a hub invocation: `{I, R, E, D, H, S}` or progress `P`.
final class InvocationResult extends ServerMessage {
  /// Creates an invocation result.
  const InvocationResult({
    required this.id,
    this.result,
    this.error,
    this.errorData,
    this.isHubException = false,
    this.state,
    this.progress,
    this.progressId,
  });

  /// Callback id.
  final String id;

  /// Return value (`R`).
  final Object? result;

  /// Error message (`E`).
  final String? error;

  /// Error data (`D`).
  final Object? errorData;

  /// `H`: the error is a `HubException` thrown on purpose by the server.
  final bool isHubException;

  /// Updated hub state (`S`).
  final Map<String, dynamic>? state;

  /// Progress data (`P.D`), set for progress messages only.
  final Object? progress;

  /// Id of the invocation a progress message belongs to.
  final String? progressId;

  /// Whether this is a progress notification.
  bool get isProgress => progressId != null;

  /// Whether the invocation failed.
  bool get hasError => error != null;
}
