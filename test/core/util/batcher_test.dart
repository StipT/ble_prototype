import 'package:ble_prototype/core/util/batcher.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<List<int>> batches;
  late Batcher<int> batcher;

  setUp(() {
    batches = [];
    batcher = Batcher<int>(onBatch: batches.add, maxCount: 3);
  });

  test('flushes synchronously when maxCount is reached', () {
    fakeAsync((async) {
      [1, 2, 3, 4].forEach(batcher.add);
      expect(batches, [
        [1, 2, 3],
      ]);
      expect(batcher.pending, 1);
    });
  });

  test('flushes maxDelay after the first buffered item', () {
    fakeAsync((async) {
      batcher.add(1);
      async.elapse(const Duration(milliseconds: 200));
      batcher.add(2);
      expect(batches, isEmpty);
      async.elapse(const Duration(milliseconds: 50));
      expect(batches, [
        [1, 2],
      ]);
      // Timer restarts with the next batch's first item.
      batcher.add(3);
      async.elapse(const Duration(milliseconds: 249));
      expect(batches, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(batches.last, [3]);
    });
  });

  test('a count flush cancels the pending timer', () {
    fakeAsync((async) {
      [1, 2, 3].forEach(batcher.add);
      async.elapse(const Duration(seconds: 1));
      expect(batches, [
        [1, 2, 3],
      ]);
    });
  });

  test('every item is emitted exactly once, in order', () {
    fakeAsync((async) {
      for (var i = 0; i < 20; i++) {
        batcher.add(i);
        async.elapse(const Duration(milliseconds: 70));
      }
      batcher.flush();
      expect(batches.expand((b) => b), List.generate(20, (i) => i));
      expect(batches.every((b) => b.length <= 3), isTrue);
    });
  });

  test('drain returns buffered items without calling onBatch', () {
    fakeAsync((async) {
      [1, 2].forEach(batcher.add);
      expect(batcher.drain(), [1, 2]);
      async.elapse(const Duration(seconds: 1));
      expect(batches, isEmpty);
      expect(batcher.pending, 0);
    });
  });

  test('flush with nothing buffered emits nothing', () {
    batcher.flush();
    expect(batches, isEmpty);
  });

  test('dispose discards buffered items and the timer', () {
    fakeAsync((async) {
      batcher
        ..add(1)
        ..dispose();
      async.elapse(const Duration(seconds: 1));
      expect(batches, isEmpty);
    });
  });
}
