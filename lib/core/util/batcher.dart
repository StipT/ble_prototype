import 'dart:async';

/// Groups items into batches flushed after [maxCount] items or [maxDelay]
/// since the first buffered item, whichever comes first.
///
/// Used to turn ~10 packets/s into one database transaction per batch: one
/// transaction per packet would fsync ten times a second and burn battery.
class Batcher<T> {
  /// [onBatch] receives every non-empty batch in arrival order.
  Batcher({
    required this.onBatch,
    this.maxCount = 50,
    this.maxDelay = const Duration(milliseconds: 250),
  }) : assert(maxCount > 0, 'maxCount must be positive');

  /// Batch consumer.
  final void Function(List<T> batch) onBatch;

  /// Flush when this many items are buffered.
  final int maxCount;

  /// Flush this long after the first item of a batch arrived.
  final Duration maxDelay;

  final List<T> _buffer = [];
  Timer? _timer;

  /// Items currently buffered.
  int get pending => _buffer.length;

  /// Buffers [item]; may synchronously emit a full batch.
  void add(T item) {
    _buffer.add(item);
    if (_buffer.length >= maxCount) {
      flush();
    } else {
      _timer ??= Timer(maxDelay, flush);
    }
  }

  /// Emits whatever is buffered now.
  void flush() {
    final batch = drain();
    if (batch.isNotEmpty) onBatch(batch);
  }

  /// Returns and clears the buffer *without* calling [onBatch].
  List<T> drain() {
    _timer?.cancel();
    _timer = null;
    final batch = List<T>.of(_buffer);
    _buffer.clear();
    return batch;
  }

  /// Cancels the timer and discards buffered items.
  void dispose() => drain();
}
