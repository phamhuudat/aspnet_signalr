import 'dart:async';

import '../domain/exceptions/signalr_exception.dart';
import 'hub_connection.dart';

/// Keeps several named, independent connections together.
class HubConnectionManager {
  final _connections = <String, HubConnection>{};

  /// Registered names.
  Iterable<String> get names => _connections.keys;

  /// Registered connections.
  Map<String, HubConnection> get connections => Map.unmodifiable(_connections);

  /// Registers [connection] under [name]. Throws if [name] is used.
  void add(String name, HubConnection connection) {
    if (_connections.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'already registered');
    }
    _connections[name] = connection;
  }

  /// Unregisters [name] without stopping it.
  HubConnection? remove(String name) => _connections.remove(name);

  /// The connection named [name].
  HubConnection? get(String name) => _connections[name];

  /// Same as [get].
  HubConnection? operator [](String name) => _connections[name];

  /// Starts every connection in parallel. If some fail, the others keep
  /// running and a [HubConnectionManagerException] lists the failures.
  Future<void> startAll() async {
    final errors = <String, Object>{};
    await Future.wait([
      for (final e in _connections.entries)
        e.value.start().catchError((Object err) {
          errors[e.key] = err;
        }),
    ]);
    if (errors.isNotEmpty) throw HubConnectionManagerException(errors);
  }

  /// Starts one connection.
  Future<void> start(String name) => _require(name).start();

  /// Stops one connection; the others are not affected.
  Future<void> stop(String name) => _require(name).stop();

  /// Stops every connection.
  Future<void> stopAll() =>
      Future.wait([for (final c in _connections.values) c.stop()]);

  HubConnection _require(String name) =>
      _connections[name] ??
      (throw ArgumentError.value(name, 'name', 'not registered'));
}
