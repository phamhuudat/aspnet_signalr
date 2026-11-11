import '../domain/entities/connection_state.dart';
import '../domain/entities/transport_type.dart';
import 'hub_proxy.dart';

/// A connection to an ASP.NET SignalR 2.x endpoint.
///
/// Every instance is independent: own transport, HTTP client, proxy, state
/// and reconnect loop.
abstract interface class HubConnection {
  /// Current state.
  ConnectionState get state;

  /// State changes (the current value is not replayed).
  Stream<ConnectionState> get stateStream;

  /// The transport in use, `null` when not connected.
  TransportType? get transport;

  /// Server assigned id of the current connection.
  String? get connectionId;

  /// Creates (or returns) the proxy of [hubName]. Must be called before
  /// [start].
  HubProxy createHubProxy(String hubName);

  /// Negotiates, opens a transport and calls `/start`.
  Future<void> start();

  /// Stops the connection and the reconnect loop. Safe to call any time.
  Future<void> stop();

  /// Called when no frame was received for 2/3 of `KeepAliveTimeout`.
  void onConnectionSlow(void Function() callback);

  /// Called when the transport is lost and reconnecting starts.
  void onReconnecting(void Function(Object? error) callback);

  /// Called after a successful reconnect. [newConnection] is `true` when a
  /// new connection had to be negotiated (groups must be joined again).
  void onReconnected(void Function(bool newConnection) callback);

  /// Called when the connection becomes [ConnectionState.disconnected]
  /// after having been started. [error] is `null` for `stop()`.
  void onClosed(void Function(Object? error) callback);
}
