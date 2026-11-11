import '../domain/policies/reconnect_policy.dart';

/// Retries after each delay of [delays], then gives up.
class DefaultReconnectPolicy implements ReconnectPolicy {
  /// Creates the policy. Default delays: 0s, 2s, 10s, 30s.
  const DefaultReconnectPolicy({
    this.delays = const [
      Duration.zero,
      Duration(seconds: 2),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  });

  /// Delay before each attempt.
  final List<Duration> delays;

  @override
  Duration? nextRetryDelay(RetryContext context) =>
      context.previousRetryCount < delays.length
          ? delays[context.previousRetryCount]
          : null;
}

/// Retries forever with exponential back-off capped at [maxDelay].
class ForeverReconnectPolicy implements ReconnectPolicy {
  /// Creates the policy.
  const ForeverReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  /// Delay of the second attempt (the first one is immediate).
  final Duration initialDelay;

  /// Upper bound.
  final Duration maxDelay;

  @override
  Duration? nextRetryDelay(RetryContext context) {
    if (context.previousRetryCount == 0) return Duration.zero;
    final factor = 1 << (context.previousRetryCount - 1).clamp(0, 16);
    final d = initialDelay * factor;
    return d > maxDelay ? maxDelay : d;
  }
}

/// The SignalR 2.x behavior without automatic reconnect: try `/reconnect`
/// every 2 seconds while the reconnect window is open, never renegotiate.
class ProtocolReconnectPolicy implements ReconnectPolicy {
  /// Creates the policy.
  const ProtocolReconnectPolicy(this.window);

  /// `DisconnectTimeout` + `KeepAliveTimeout`.
  final Duration window;

  @override
  Duration? nextRetryDelay(RetryContext context) {
    if (context.elapsed >= window) return null;
    return context.previousRetryCount == 0
        ? Duration.zero
        : const Duration(seconds: 2);
  }
}
