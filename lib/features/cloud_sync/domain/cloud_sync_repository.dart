import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import 'entities/sync_counts.dart';

/// Upload engine: moves local chunks to the cloud and prunes old ones.
///
/// Chunk lifecycle (`ChunkSyncState`): `pending -> uploading -> synced`, or
/// back to `pending` with a backoff delay after a transient failure, or
/// `failed` once the retry cap is reached.
abstract interface class CloudSyncRepository {
  /// Crash recovery: chunks left in `uploading` by an app that died
  /// mid-upload go back to `pending`. Call once at startup, before any run.
  /// Returns how many were reset.
  Future<Result<int, Failure>> recoverInterrupted();

  /// Uploads every eligible chunk: `pending`, not pruned, past its backoff
  /// deadline, and either full or belonging to an ended session.
  ///
  /// With [manual] (the "Sync now" button) `failed` chunks are reset to
  /// `pending` with zero attempts and backoff deadlines are ignored.
  ///
  /// Returns `Err` only when the run could not start (sign-in or database
  /// error); per-chunk failures are recorded on the chunks.
  Future<Result<SyncReport, Failure>> uploadEligible({bool manual = false});

  /// Deletes the local packets of `synced` chunks that started more than
  /// the retention period ago, keeping each chunk row as a tombstone
  /// (`prunedAt`) so it is never uploaded again. Returns pruned chunks.
  Future<Result<int, Failure>> pruneSynced();

  /// Chunk counts per state; re-emits on every change.
  Stream<SyncCounts> watchCounts();
}
