import 'dart:async';

import '../domain/entities/connection_state.dart';

/// Holds the connection state and broadcasts changes.
class ConnectionStateMachine {
  ConnectionState _state = ConnectionState.disconnected;
  final _controller = StreamController<ConnectionState>.broadcast(sync: true);

  /// Current state.
  ConnectionState get state => _state;

  /// Changes, without the current value.
  Stream<ConnectionState> get stream => _controller.stream;

  /// Moves to [next]; returns `false` if already there.
  bool transition(ConnectionState next) {
    if (_state == next) return false;
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
    return true;
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}
