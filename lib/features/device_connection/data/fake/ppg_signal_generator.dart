import 'dart:math' as math;

/// Synthesizes a plausible raw PPG signal: a sum of sines for the cardiac
/// pulse, a slow respiration-driven baseline drift and amplitude
/// modulation, plus Gaussian noise. Output is unsigned 24-bit like a real
/// optical front-end (e.g. MAX3010x) would deliver.
///
/// Phase is accumulated per sample, so changing [heartRateBpm] mid-stream
/// does not produce a discontinuity.
class PpgSignalGenerator {
  /// [heartRateBpm] sets the pulse frequency, [sampleRateHz] the output rate,
  /// [respirationRateBpm] the baseline drift frequency, [noiseLevel] the
  /// noise standard deviation relative to pulse amplitude, and [random]
  /// allows deterministic tests.
  PpgSignalGenerator({
    this.heartRateBpm = 72,
    this.sampleRateHz = 50,
    this.respirationRateBpm = 15,
    this.noiseLevel = 0.03,
    math.Random? random,
  }) : _random = random ?? math.Random();

  /// Pulse rate in beats per minute; can be changed at any time.
  double heartRateBpm;

  /// Samples per second.
  final int sampleRateHz;

  /// Breaths per minute driving the baseline drift.
  double respirationRateBpm;

  /// Noise standard deviation, relative to pulse amplitude.
  double noiseLevel;

  final math.Random _random;
  double _cardiacPhase = 0;
  double _respPhase = 0;

  static const _baseline = 8000000.0;
  static const _amplitude = 40000.0;
  static const _maxValue = 0xFFFFFF;

  /// Produces the next [count] samples.
  List<int> next(int count) => List<int>.generate(count, (_) => _sample());

  int _sample() {
    final dt = 1 / sampleRateHz;
    _cardiacPhase += 2 * math.pi * (heartRateBpm / 60) * dt;
    _respPhase += 2 * math.pi * (respirationRateBpm / 60) * dt;
    _cardiacPhase %= 2 * math.pi;
    _respPhase %= 2 * math.pi;

    final p = _cardiacPhase;
    // Fundamental + harmonics shape a steep systolic upstroke and a
    // dicrotic notch on the down slope.
    final pulse =
        math.sin(p) +
        0.45 * math.sin(2 * p + 0.8) +
        0.2 * math.sin(3 * p + 1.6);
    final drift = 0.6 * math.sin(_respPhase);
    final modulation = 1 + 0.1 * math.sin(_respPhase);
    final value =
        _baseline +
        _amplitude * (pulse * modulation + drift + noiseLevel * _gaussian());
    return value.round().clamp(0, _maxValue);
  }

  double _gaussian() {
    // Box-Muller transform.
    final u1 = 1 - _random.nextDouble();
    final u2 = _random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
