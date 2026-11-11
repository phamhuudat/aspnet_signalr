/// The lifecycle state of a `HubConnection`.
enum ConnectionState {
  /// `start()` is negotiating and opening a transport.
  connecting,

  /// The transport is open and `/start` succeeded.
  connected,

  /// The transport was lost and the client is trying to get it back.
  reconnecting,

  /// Not connected. Either never started, stopped, or reconnect gave up.
  disconnected,
}
