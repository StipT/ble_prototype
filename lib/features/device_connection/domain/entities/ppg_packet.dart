import 'package:equatable/equatable.dart';

/// Whether a packet was pushed live or replayed from the device's backlog.
enum PpgPacketKind {
  /// Sent right after the samples were measured, while the app is listening.
  live,

  /// Re-sent from the device's internal storage in answer to a history
  /// request (the app was disconnected or a live packet was dropped).
  history,
}

/// One decoded PPG notification: a run of consecutive samples.
///
/// A BLE notification is limited by the negotiated MTU, so the device sends
/// the signal as many small packets. The [sequence] number increases by one
/// per packet and never resets while the device is powered on; that is what
/// lets the app detect gaps (dropped notifications) and ask for exactly the
/// missing ranges later.
class PpgPacket extends Equatable {
  /// Creates a packet.
  ///
  /// [sequence] is the device-wide monotonically increasing packet counter.
  /// [timestamp] is the wall-clock time of the first sample in [samples].
  /// [samples] are raw unsigned 24-bit ADC readings (0..16 777 215).
  /// [kind] tells whether it arrived live or as a history replay.
  const PpgPacket({
    required this.sequence,
    required this.timestamp,
    required this.samples,
    this.kind = PpgPacketKind.live,
  });

  /// Device-wide packet counter (unsigned 32 bit).
  final int sequence;

  /// Time of the first sample, as reported by the device clock.
  final DateTime timestamp;

  /// Raw 24-bit light-intensity readings, oldest first.
  final List<int> samples;

  /// Live or history packet.
  final PpgPacketKind kind;

  /// Copy with a different [kind].
  PpgPacket copyWith({PpgPacketKind? kind}) => PpgPacket(
    sequence: sequence,
    timestamp: timestamp,
    samples: samples,
    kind: kind ?? this.kind,
  );

  @override
  List<Object?> get props => [sequence, timestamp, samples, kind];

  @override
  String toString() =>
      'PpgPacket(#$sequence, ${kind.name}, ${samples.length} samples)';
}
