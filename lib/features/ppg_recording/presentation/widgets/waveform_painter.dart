import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws raw PPG samples as an auto-scaled polyline.
class WaveformPainter extends CustomPainter {
  /// [samples] oldest first; [capacity] is the number of samples the full
  /// width represents (so the trace scrolls in from the right); [color] is
  /// the stroke colour.
  WaveformPainter({
    required this.samples,
    required this.capacity,
    required this.color,
  });

  /// Samples to draw.
  final List<int> samples;

  /// Samples per full width.
  final int capacity;

  /// Stroke colour.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    var lo = samples.first;
    var hi = samples.first;
    for (final s in samples) {
      lo = math.min(lo, s);
      hi = math.max(hi, s);
    }
    final range = math.max(1, hi - lo);
    final dx = size.width / math.max(1, capacity - 1);
    final x0 = size.width - (samples.length - 1) * dx;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      // Light absorption rises with blood volume, so the raw signal is
      // inverted to show the familiar upward systolic peak.
      final y = size.height * (samples[i] - lo) / range;
      final x = x0 + i * dx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      !identical(oldDelegate.samples, samples) || oldDelegate.color != color;
}

/// Sized wrapper around [WaveformPainter].
class LiveWaveform extends StatelessWidget {
  /// Shows [samples] scaled to [capacity] samples per width.
  const LiveWaveform({
    super.key,
    required this.samples,
    required this.capacity,
  });

  /// Samples to draw.
  final List<int> samples;

  /// Samples per full width.
  final int capacity;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: WaveformPainter(
        samples: samples,
        capacity: capacity,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
