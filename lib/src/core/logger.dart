/// Log severity.
enum LogLevel {
  /// Every frame.
  trace,

  /// Requests and state changes.
  debug,

  /// Important events.
  info,

  /// Recoverable problems.
  warning,

  /// Failures.
  error,

  /// Nothing.
  none,
}

/// Receives log records from a connection.
abstract interface class SignalRLogger {
  /// Writes one record.
  void log(LogLevel level, String message, [Object? error]);
}

/// Logs nothing.
class NoopLogger implements SignalRLogger {
  /// Creates a logger that discards everything.
  const NoopLogger();

  @override
  void log(LogLevel level, String message, [Object? error]) {}
}

/// Prints records at or above [level].
class PrintLogger implements SignalRLogger {
  /// Creates a print logger.
  const PrintLogger({this.level = LogLevel.info, this.tag = 'aspnet_signalr'});

  /// Minimum level printed.
  final LogLevel level;

  /// Prefix of every line.
  final String tag;

  @override
  void log(LogLevel level, String message, [Object? error]) {
    if (level.index < this.level.index || level == LogLevel.none) return;
    // ignore: avoid_print
    print('[$tag] ${level.name.toUpperCase()} $message'
        '${error != null ? ' | $error' : ''}');
  }
}

/// Adds a prefix (the connection name) to every record.
class PrefixedLogger implements SignalRLogger {
  /// Wraps [inner].
  const PrefixedLogger(this.inner, this.prefix);

  /// The wrapped logger.
  final SignalRLogger inner;

  /// The prefix.
  final String prefix;

  @override
  void log(LogLevel level, String message, [Object? error]) =>
      inner.log(level, '$prefix $message', error);
}
