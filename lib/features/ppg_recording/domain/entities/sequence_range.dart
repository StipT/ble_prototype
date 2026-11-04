import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// An inclusive run of device packet sequence numbers, `from..to`.
///
/// The wearable numbers every BLE notification it produces with a
/// device-wide, monotonically increasing sequence number. That makes "what
/// am I missing?" a pure arithmetic question: anything between two stored
/// numbers that is not in the database is a gap, and the device's history
/// request (`RequestHistoryCommand`) takes exactly such a range.
class SequenceRange extends Equatable {
  /// Creates the range [from]..[to] (both inclusive, `from <= to`).
  const SequenceRange(this.from, this.to)
    : assert(from <= to, 'from must not exceed to');

  /// First missing sequence number (inclusive).
  final int from;

  /// Last missing sequence number (inclusive).
  final int to;

  /// Number of packets in the range.
  int get length => to - from + 1;

  /// Intersection with [lo]..[hi], or `null` when they don't overlap.
  ///
  /// Used to clip a gap to what the device can still replay: its backlog is
  /// a ring buffer holding only `oldestSequence..latestSequence`, so asking
  /// for anything older is pointless.
  SequenceRange? clamp(int lo, int hi) {
    final f = math.max(from, lo);
    final t = math.min(to, hi);
    return f <= t ? SequenceRange(f, t) : null;
  }

  /// Splits the range into consecutive pieces of at most [maxLength]
  /// packets.
  ///
  /// Small history requests are cheaper to lose: if the link drops in the
  /// middle of one, only that piece is re-requested after reconnecting.
  List<SequenceRange> split(int maxLength) {
    assert(maxLength > 0, 'maxLength must be positive');
    return [
      for (var f = from; f <= to; f += maxLength)
        SequenceRange(f, math.min(to, f + maxLength - 1)),
    ];
  }

  @override
  List<Object?> get props => [from, to];

  @override
  String toString() => 'SequenceRange($from..$to)';
}
