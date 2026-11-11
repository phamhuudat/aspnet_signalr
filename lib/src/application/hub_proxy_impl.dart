import '../core/logger.dart';
import '../domain/entities/hub_message.dart';
import '../presentation/hub_proxy.dart';

/// Sends invocations for a [HubProxyImpl].
abstract interface class HubInvoker {
  /// Invokes [method] on [hub] and returns the raw result.
  Future<Object?> invokeHub(
    HubProxyImpl hub,
    String method,
    List<Object?> args,
    Duration? timeout,
  );
}

/// Default [HubProxy].
class HubProxyImpl implements HubProxy {
  /// Creates a proxy.
  HubProxyImpl(this.hubName, this._invoker, this._logger);

  @override
  final String hubName;

  final HubInvoker _invoker;
  final SignalRLogger _logger;
  final _handlers = <String, List<HubMethodHandler>>{};

  @override
  final Map<String, dynamic> state = {};

  /// Name sent in `connectionData` and `H` (lower case, like the JS client).
  String get wireName => hubName.toLowerCase();

  @override
  void on(String method, HubMethodHandler handler) =>
      (_handlers[method.toLowerCase()] ??= []).add(handler);

  @override
  void off(String method, [HubMethodHandler? handler]) {
    final key = method.toLowerCase();
    if (handler == null) {
      _handlers.remove(key);
    } else {
      _handlers[key]?.remove(handler);
      if (_handlers[key]?.isEmpty ?? false) _handlers.remove(key);
    }
  }

  @override
  Future<T> invoke<T>(
    String method, [
    List<Object?> args = const [],
    Duration? timeout,
  ]) async {
    final raw = await _invoker.invokeHub(this, method, args, timeout);
    if (raw is int && T == double) return raw.toDouble() as T;
    return raw as T;
  }

  /// Merges server state.
  void updateState(Map<String, dynamic>? s) {
    if (s != null) state.addAll(s);
  }

  /// Delivers a server call to the handlers.
  void dispatch(HubMessage message) {
    updateState(message.state);
    final handlers = _handlers[message.method.toLowerCase()];
    if (handlers == null || handlers.isEmpty) {
      _logger.log(
        LogLevel.trace,
        'No handler for $hubName.${message.method}',
      );
      return;
    }
    for (final h in List.of(handlers)) {
      try {
        h(message.args);
      } catch (e) {
        _logger.log(
          LogLevel.error,
          'Handler $hubName.${message.method} threw',
          e,
        );
      }
    }
  }
}
