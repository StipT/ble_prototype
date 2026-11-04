import 'package:ble_prototype/features/cloud_sync/domain/upload_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delays double from the initial delay and are capped', () {
    const p = UploadRetryPolicy(
      initialDelay: Duration(seconds: 30),
      maxDelay: Duration(minutes: 3),
    );
    expect(
      [for (var n = 1; n <= 5; n++) p.delayAfter(n).inSeconds],
      [30, 60, 120, 180, 180],
    );
  });

  test('exhausted after maxAttempts failed attempts', () {
    const p = UploadRetryPolicy(maxAttempts: 3);
    expect(p.exhausted(2), isFalse);
    expect(p.exhausted(3), isTrue);
  });
}
