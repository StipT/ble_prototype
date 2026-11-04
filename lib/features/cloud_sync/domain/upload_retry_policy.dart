import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Per-chunk exponential backoff with a retry cap.
///
/// After failed attempt `n` (1-based) the chunk waits
/// `min(initialDelay * multiplier^(n-1), maxDelay)` before it is due again.
/// When `n` reaches [maxAttempts] the chunk moves to `failed` and is only
/// retried when the user presses "Sync now".
class UploadRetryPolicy extends Equatable {
  /// Defaults: 30 s, 60 s, 120 s, 240 s, then give up after 5 attempts.
  const UploadRetryPolicy({
    this.initialDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(hours: 1),
    this.multiplier = 2,
    this.maxAttempts = 5,
  }) : assert(maxAttempts > 0, 'maxAttempts must be positive');

  /// Wait after the first failure.
  final Duration initialDelay;

  /// Upper bound for any wait.
  final Duration maxDelay;

  /// Growth factor between consecutive waits.
  final double multiplier;

  /// Failed attempts after which a chunk becomes `failed`.
  final int maxAttempts;

  /// Wait after failed attempt number [attempts] (1-based).
  Duration delayAfter(int attempts) {
    assert(attempts >= 1, 'attempts are 1-based');
    final micros =
        initialDelay.inMicroseconds * math.pow(multiplier, attempts - 1);
    if (micros >= maxDelay.inMicroseconds) return maxDelay;
    return Duration(microseconds: micros.round());
  }

  /// Whether a chunk with [attempts] failed attempts has given up.
  bool exhausted(int attempts) => attempts >= maxAttempts;

  @override
  List<Object?> get props => [initialDelay, maxDelay, multiplier, maxAttempts];
}
