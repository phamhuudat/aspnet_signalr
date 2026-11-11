import '../entities/connection_info.dart';
import '../entities/server_message.dart';
import '../entities/transport_type.dart';

/// Called for each frame received from the server.
typedef MessageHandler = void Function(ServerMessage message);

/// Called once when an open transport is lost (not after [ClientTransport.close]).
typedef CloseHandler = void Function(Object? error);

/// Position in the message stream, used by `/reconnect` and `/poll`.
class ReconnectCursor {
  /// Creates a cursor.
  const ReconnectCursor({this.messageId, this.groupsToken});

  /// Last `C` value.
  final String? messageId;

  /// Last `G` value.
  final String? groupsToken;
}

/// A SignalR transport.
abstract interface class ClientTransport {
  /// The concrete transport in use. For `auto`, the selected one after
  /// connect, or [TransportType.auto] before.
  TransportType get type;

  /// Opens the transport.
  ///
  /// Without [reconnect], completes after the init message (`S: 1`).
  /// With [reconnect], calls `/reconnect` and completes once it is open.
  Future<void> connect(
    ConnectionInfo info, {
    required MessageHandler onMessage,
    required CloseHandler onClose,
    ReconnectCursor? reconnect,
  });

  /// Sends a JSON payload to the server.
  Future<void> send(String payload);

  /// Closes the transport. [CloseHandler] is not called.
  Future<void> close();
}
