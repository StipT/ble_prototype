import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Capped exponential backoff for BLE reconnects.
///
/// Why back off at all? After a drop the wearable is often simply out of
/// range. Hammering `connect` keeps the phone's radio busy (battery!) and on
/// Android repeated failed GATT connects can exhaust the stack's client
/// slots (the infamous status 133). Doubling the wait gives quick recovery
/// from short glitches (1 s, 2 s, 4 s, ...) while the cap ([maxDelay])
/// guarantees the app still notices within a bounded time once the user
/// walks back into range.
///
/// Delay of attempt `n` (1-based): `min(initialDelay * multiplier^(n-1),
/// maxDelay)`.
class ReconnectPolicy extends Equatable {
  /// [initialDelay] is the wait before the first attempt, [multiplier] the
  /// growth factor, [maxDelay] the cap, and [maxAttempts] how many attempts
  /// to make before giving up (`null` = keep trying forever, which suits a
  /// wearable that is expected to come back).
  const ReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2,
    this.maxAttempts,
  });

  /// Wait before attempt 1.
  final Duration initialDelay;

  /// Upper bound for any single wait.
  final Duration maxDelay;

  /// Growth factor between consecutive attempts.
  final double multiplier;

  /// Give up after this many failed attempts; `null` never gives up.
  final int? maxAttempts;

  /// Wait before the 1-based [attempt].
  Duration delayFor(int attempt) {
    assert(attempt >= 1, 'attempts are 1-based');
    final micros =
        initialDelay.inMicroseconds * math.pow(multiplier, attempt - 1);
    if (micros >= maxDelay.inMicroseconds) return maxDelay;
    return Duration(microseconds: micros.round());
  }

  /// Whether another attempt numbered [attempt] is allowed.
  bool allows(int attempt) => maxAttempts == null || attempt <= maxAttempts!;

  @override
  List<Object?> get props => [initialDelay, maxDelay, multiplier, maxAttempts];
}
