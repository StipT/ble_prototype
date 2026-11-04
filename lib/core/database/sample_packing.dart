import 'dart:typed_data';

/// Packs and unpacks unsigned 24-bit samples (3 bytes, little-endian).
///
/// Same layout as on the wire, so storing a packet costs 3 bytes per sample
/// instead of 8 for a SQLite INTEGER per row.
abstract final class SamplePacking {
  /// Packs [samples] (0..0xFFFFFF each).
  static Uint8List pack(List<int> samples) {
    final out = Uint8List(samples.length * 3);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      out[i * 3] = s & 0xFF;
      out[i * 3 + 1] = (s >> 8) & 0xFF;
      out[i * 3 + 2] = (s >> 16) & 0xFF;
    }
    return out;
  }

  /// Unpacks a blob produced by [pack].
  static List<int> unpack(Uint8List bytes) => List<int>.generate(
    bytes.length ~/ 3,
    (i) => bytes[i * 3] | (bytes[i * 3 + 1] << 8) | (bytes[i * 3 + 2] << 16),
    growable: false,
  );
}
