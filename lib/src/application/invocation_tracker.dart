import 'dart:async';

import '../domain/entities/server_message.dart';

/// Matches invocation results to pending calls.
class InvocationTracker {
  int _next = 0;
  final _pending = <String, Completer<InvocationResult>>{};

  /// Number of calls waiting for a result.
  int get pendingCount => _pending.length;

  /// Registers a new call and returns its id and result future.
  (String, Future<InvocationResult>) register() {
    final id = '${_next++}';
    final completer = Completer<InvocationResult>();
    _pending[id] = completer;
    return (id, completer.future);
  }

  /// Completes the matching call. Progress messages are ignored.
  bool complete(InvocationResult result) {
    if (result.isProgress) return false;
    final completer = _pending.remove(result.id);
    if (completer == null) return false;
    completer.complete(result);
    return true;
  }

  /// Fails one call.
  void fail(String id, Object error) {
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  /// Forgets one call without completing it.
  void remove(String id) => _pending.remove(id);

  /// Fails every pending call.
  void failAll(Object error) {
    final all = _pending.values.toList();
    _pending.clear();
    for (final c in all) {
      if (!c.isCompleted) c.completeError(error);
    }
  }
}
