import 'package:equatable/equatable.dart';

/// Number of local chunks per upload state, across all sessions.
class SyncCounts extends Equatable {
  /// Creates the counts.
  const SyncCounts({
    this.pending = 0,
    this.uploading = 0,
    this.synced = 0,
    this.failed = 0,
    this.pruned = 0,
  });

  /// Waiting for upload (includes chunks of a running session that are not
  /// full yet, and chunks waiting for a backoff delay).
  final int pending;

  /// Upload in flight.
  final int uploading;

  /// Stored in Firestore (includes [pruned]).
  final int synced;

  /// Gave up after the retry cap (or a permanent error); "Sync now" retries.
  final int failed;

  /// Synced chunks whose local packets were deleted (tombstones).
  final int pruned;

  /// All chunks.
  int get total => pending + uploading + synced + failed;

  @override
  List<Object?> get props => [pending, uploading, synced, failed, pruned];
}

/// Outcome of one upload run.
class SyncReport extends Equatable {
  /// Creates the report.
  const SyncReport({
    this.uploaded = 0,
    this.retryScheduled = 0,
    this.failed = 0,
    this.nextRetryAt,
  });

  /// Chunks that reached `synced` in this run.
  final int uploaded;

  /// Chunks that failed transiently and went back to `pending` with a
  /// backoff delay.
  final int retryScheduled;

  /// Chunks that reached `failed` in this run.
  final int failed;

  /// Earliest backoff deadline of any pending chunk, if one is waiting;
  /// the bloc schedules an automatic retry for it.
  final DateTime? nextRetryAt;

  @override
  List<Object?> get props => [uploaded, retryScheduled, failed, nextRetryAt];
}
