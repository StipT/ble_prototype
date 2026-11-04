import 'package:equatable/equatable.dart';

/// A recording session.
class Session extends Equatable {
  /// Creates a session.
  const Session({
    required this.id,
    required this.deviceId,
    required this.startedAt,
    required this.sampleRateHz,
    this.endedAt,
  });

  /// Unique ID.
  final String id;

  /// Wearable that produced the data.
  final String deviceId;

  /// Start time.
  final DateTime startedAt;

  /// End time; `null` while recording.
  final DateTime? endedAt;

  /// Samples per second.
  final int sampleRateHz;

  /// Whether the session is still recording.
  bool get isActive => endedAt == null;

  @override
  List<Object?> get props => [id, deviceId, startedAt, endedAt, sampleRateHz];
}

/// Session plus aggregates for the sessions list.
class SessionSummary extends Equatable {
  /// Creates a summary.
  const SessionSummary({
    required this.session,
    required this.packetCount,
    required this.historyPacketCount,
    required this.firstSequence,
    required this.lastSequence,
    required this.chunkCount,
    required this.pendingChunks,
    required this.uploadingChunks,
    required this.syncedChunks,
    required this.failedChunks,
  });

  /// The session.
  final Session session;

  /// Stored packets.
  final int packetCount;

  /// Of which recovered through history sync.
  final int historyPacketCount;

  /// Lowest stored sequence (null when empty).
  final int? firstSequence;

  /// Highest stored sequence (null when empty).
  final int? lastSequence;

  /// Chunks in total.
  final int chunkCount;

  /// Chunks waiting for upload.
  final int pendingChunks;

  /// Chunks being uploaded.
  final int uploadingChunks;

  /// Chunks stored in the cloud.
  final int syncedChunks;

  /// Chunks that hit the retry cap.
  final int failedChunks;

  /// Packets missing between first and last stored sequence.
  int get missingPackets => firstSequence == null
      ? 0
      : lastSequence! - firstSequence! + 1 - packetCount;

  /// Recorded duration in seconds, based on stored samples.
  double durationSeconds(int samplesPerPacket) =>
      packetCount * samplesPerPacket / session.sampleRateHz;

  @override
  List<Object?> get props => [
    session,
    packetCount,
    historyPacketCount,
    firstSequence,
    lastSequence,
    chunkCount,
    pendingChunks,
    uploadingChunks,
    syncedChunks,
    failedChunks,
  ];
}
