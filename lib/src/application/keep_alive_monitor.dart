import 'dart:async';

/// Watches server activity.
///
/// Calls [onSlow] after 2/3 of [timeout] without any frame, and [onTimeout]
/// after [timeout]. Uses at most one timer, rescheduled lazily, so frequent
/// frames do not create timers.
class KeepAliveMonitor {
  /// Creates the monitor.
  KeepAliveMonitor({
    required this.timeout,
    required this.onSlow,
    required this.onTimeout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Keep-alive timeout from negotiate.
  final Duration timeout;

  /// Called once per silence period at 2/3 of [timeout].
  final void Function() onSlow;

  /// Called when [timeout] elapsed without activity.
  final void Function() onTimeout;

  final DateTime Function() _clock;
  DateTime _last = DateTime.now();
  Timer? _timer;
  bool _slowRaised = false;
  bool _running = false;

  /// Time of the last frame.
  DateTime get lastActivity => _last;

  Duration get _slowAfter => timeout * 2 ~/ 3;

  /// Starts monitoring.
  void start() {
    _running = true;
    markActivity();
    _schedule(_slowAfter);
  }

  /// Records a frame.
  void markActivity() {
    _last = _clock();
    _slowRaised = false;
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d < Duration.zero ? Duration.zero : d, _check);
  }

  void _check() {
    if (!_running) return;
    final silent = _clock().difference(_last);
    if (silent >= timeout) {
      stop();
      onTimeout();
      return;
    }
    if (silent >= _slowAfter) {
      if (!_slowRaised) {
        _slowRaised = true;
        onSlow();
      }
      _schedule(timeout - silent);
    } else {
      _schedule(_slowAfter - silent);
    }
  }

  /// Stops monitoring.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}
