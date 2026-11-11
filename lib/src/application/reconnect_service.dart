import 'dart:async';

import '../core/logger.dart';
import '../domain/policies/reconnect_policy.dart';

/// How a reconnect loop ended.
enum ReconnectOutcome {
  /// `/reconnect` succeeded: same connection id, groups and cursor kept.
  reconnected,

  /// The reconnect window was over; a new connection was negotiated.
  restarted,

  /// The policy gave up.
  gaveUp,

  /// `stop()` was called.
  cancelled,
}

/// Drives reconnect attempts.
///
/// While the reconnect window (`DisconnectTimeout` + `KeepAliveTimeout`,
/// counted from the last server activity) is open, each attempt calls
/// `/reconnect` with the last `messageId` and `groupsToken`. After that, if
/// [allowRestart], each attempt negotiates a brand new connection.
class ReconnectService {
  /// Creates the service.
  ReconnectService({
    required this.policy,
    required this.window,
    required this.allowRestart,
    required this.reconnectTransport,
    required this.restart,
    this.logger = const NoopLogger(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Retry policy.
  final ReconnectPolicy policy;

  /// Reconnect window.
  final Duration window;

  /// Whether to renegotiate after the window.
  final bool allowRestart;

  /// One `/reconnect` attempt.
  final Future<void> Function() reconnectTransport;

  /// One full negotiate/connect/start attempt.
  final Future<void> Function() restart;

  /// Logger.
  final SignalRLogger logger;

  final DateTime Function() _clock;
  bool _cancelled = false;
  Completer<void>? _sleep;

  /// Error of the last failed attempt.
  Object? lastError;

  /// Stops the loop as soon as possible.
  void cancel() {
    _cancelled = true;
    final s = _sleep;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<void> _wait(Duration d) async {
    if (d <= Duration.zero) return;
    final s = _sleep = Completer<void>();
    final t = Timer(d, () {
      if (!s.isCompleted) s.complete();
    });
    await s.future;
    t.cancel();
  }

  /// Runs until success, give-up or cancel.
  Future<ReconnectOutcome> run({
    required DateTime lastActive,
    Object? error,
  }) async {
    final lostAt = _clock();
    lastError = error;
    var retries = 0;
    while (!_cancelled) {
      final delay = policy.nextRetryDelay(
        RetryContext(
          previousRetryCount: retries,
          elapsed: _clock().difference(lostAt),
          lastError: lastError,
        ),
      );
      if (delay == null) return ReconnectOutcome.gaveUp;
      await _wait(delay);
      if (_cancelled) break;
      final inWindow = _clock().difference(lastActive) < window;
      if (!inWindow && !allowRestart) return ReconnectOutcome.gaveUp;
      try {
        if (inWindow) {
          logger.log(LogLevel.info, 'Reconnect attempt ${retries + 1}');
          await reconnectTransport();
          if (_cancelled) break;
          return ReconnectOutcome.reconnected;
        }
        logger.log(LogLevel.info, 'Restart attempt ${retries + 1}');
        await restart();
        if (_cancelled) break;
        return ReconnectOutcome.restarted;
      } catch (e) {
        lastError = e;
        retries++;
        logger.log(LogLevel.info, 'Attempt $retries failed', e);
      }
    }
    return ReconnectOutcome.cancelled;
  }
}
