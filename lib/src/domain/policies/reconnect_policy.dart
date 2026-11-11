import 'package:meta/meta.dart';

/// Information passed to [ReconnectPolicy.nextRetryDelay].
@immutable
class RetryContext {
  /// Creates a retry context.
  const RetryContext({
    required this.previousRetryCount,
    required this.elapsed,
    this.lastError,
  });

  /// Number of failed attempts so far.
  final int previousRetryCount;

  /// Time since the connection was lost.
  final Duration elapsed;

  /// The error of the last attempt (or of the lost transport).
  final Object? lastError;
}

/// Decides when to retry after the connection was lost.
abstract interface class ReconnectPolicy {
  /// Delay before the next attempt, or `null` to give up.
  Duration? nextRetryDelay(RetryContext context);
}
