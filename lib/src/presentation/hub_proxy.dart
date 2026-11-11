/// Handles a client method call from the server. [args] are JSON decoded.
typedef HubMethodHandler = void Function(List<dynamic> args);

/// A hub on a connection. Create it with `HubConnection.createHubProxy`
/// before `start()`.
abstract interface class HubProxy {
  /// Hub name as passed to `createHubProxy`.
  String get hubName;

  /// Hub state sent with every invocation and updated by the server.
  Map<String, dynamic> get state;

  /// Subscribes [handler] to the client method [method] (case insensitive).
  void on(String method, HubMethodHandler handler);

  /// Removes [handler], or every handler of [method] when omitted.
  void off(String method, [HubMethodHandler? handler]);

  /// Calls the server method [method] and returns its result.
  ///
  /// Throws `HubInvocationException` if the server method threw, and
  /// `SignalRTimeoutException` after [timeout] (default from the builder).
  Future<T> invoke<T>(
    String method, [
    List<Object?> args = const [],
    Duration? timeout,
  ]);
}
