import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// SDK-neutral content of the Firestore session document
/// `users/{uid}/sessions/{sessionId}` (schema: `functions/README.md`).
///
/// The domain never touches Firestore types (`Timestamp`, `Blob`); the
/// remote implementation maps this value to whatever its SDK needs. That
/// keeps the upload engine testable without Firebase.
class SessionUpload extends Equatable {
  /// Creates the value.
  const SessionUpload({
    required this.sessionId,
    required this.deviceId,
    required this.startedAt,
    required this.sampleRateHz,
    this.endedAt,
  });

  /// Document id (also the local session id).
  final String sessionId;

  /// Wearable that produced the data.
  final String deviceId;

  /// Session start.
  final DateTime startedAt;

  /// Session end, `null` while still recording.
  final DateTime? endedAt;

  /// Samples per second.
  final int sampleRateHz;

  @override
  List<Object?> get props => [
    sessionId,
    deviceId,
    startedAt,
    endedAt,
    sampleRateHz,
  ];
}

/// SDK-neutral content of one chunk document
/// `users/{uid}/sessions/{sessionId}/chunks/{sessionId}_{chunkIndex}`.
///
/// Field names and meaning match `firestore.rules` exactly (the rules use
/// `hasOnly`/`hasAll`, so no field may be added or dropped).
class ChunkUpload extends Equatable {
  /// Creates the value; see the field docs for the invariants.
  const ChunkUpload({
    required this.sessionId,
    required this.chunkIndex,
    required this.firstSequence,
    required this.lastSequence,
    required this.packetCount,
    required this.samplesPerPacket,
    required this.missingSequences,
    required this.startedAt,
    required this.sampleRateHz,
    required this.deviceId,
    required this.samples,
    this.encoding = gzipU24le,
  });

  /// Value of [encoding]: gzip over unsigned 24-bit little-endian samples.
  static const gzipU24le = 'gzip-u24le';

  /// Owning session.
  final String sessionId;

  /// `sequence ~/ 100`.
  final int chunkIndex;

  /// Lowest stored sequence.
  final int firstSequence;

  /// Highest stored sequence.
  final int lastSequence;

  /// Stored packets (`<= lastSequence - firstSequence + 1`).
  final int packetCount;

  /// Samples in every packet (5 for the current codec).
  final int samplesPerPacket;

  /// Sequences between [firstSequence] and [lastSequence] that were never
  /// stored, ascending.
  final List<int> missingSequences;

  /// Timestamp of the earliest packet.
  final DateTime startedAt;

  /// Samples per second.
  final int sampleRateHz;

  /// Wearable that produced the data.
  final String deviceId;

  /// Always [gzipU24le].
  final String encoding;

  /// gzip(SamplePacking.pack(all samples in sequence order)).
  final Uint8List samples;

  /// Firestore document id. Deterministic, so a retried upload overwrites
  /// the same document instead of creating a duplicate (idempotency).
  String get docId => '${sessionId}_$chunkIndex';

  @override
  List<Object?> get props => [
    sessionId,
    chunkIndex,
    firstSequence,
    lastSequence,
    packetCount,
    samplesPerPacket,
    missingSequences,
    startedAt,
    sampleRateHz,
    deviceId,
    encoding,
    samples,
  ];
}
