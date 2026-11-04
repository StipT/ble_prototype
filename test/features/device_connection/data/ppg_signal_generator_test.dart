import 'dart:math' as math;

import 'package:ble_prototype/features/device_connection/data/fake/ppg_signal_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int countPeaks(List<int> s) {
    // Smooth to ignore noise, then count local maxima above the mean.
    final smooth = [
      for (var i = 2; i < s.length - 2; i++)
        (s[i - 2] + s[i - 1] + s[i] + s[i + 1] + s[i + 2]) / 5,
    ];
    final mean = smooth.reduce((a, b) => a + b) / smooth.length;
    var peaks = 0;
    for (var i = 3; i < smooth.length - 3; i++) {
      final w = smooth.sublist(i - 3, i + 4);
      if (smooth[i] == w.reduce(math.max) && smooth[i] > mean) peaks++;
    }
    return peaks;
  }

  test('produces 24-bit samples', () {
    final g = PpgSignalGenerator(random: math.Random(1));
    final s = g.next(1000);
    expect(s.every((v) => v >= 0 && v <= 0xFFFFFF), isTrue);
  });

  test('pulse frequency follows configured heart rate', () {
    for (final hr in [60.0, 120.0]) {
      final g = PpgSignalGenerator(
        heartRateBpm: hr,
        respirationRateBpm: 0,
        noiseLevel: 0,
        random: math.Random(1),
      );
      final beats = countPeaks(g.next(50 * 30)); // 30 s
      expect(beats, closeTo(hr / 2, hr * 0.05), reason: 'hr=$hr');
    }
  });
}
