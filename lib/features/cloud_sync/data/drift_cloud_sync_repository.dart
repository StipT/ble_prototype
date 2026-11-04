import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/cloud_remote.dart';
import '../domain/cloud_sync_repository.dart';
import '../domain/entities/cloud_documents.dart';
import '../domain/entities/sync_counts.dart';
import '../domain/upload_retry_policy.dart';
import 'chunk_encoder.dart';

/// [CloudSyncRepository] that reads chunks from Drift and writes them
/// through a [CloudRemote].
///
/// Every state transition is persisted before/after the network call, so
/// the database always tells the truth even if the app dies mid-upload
/// (see [recoverInterrupted]). Time comes from `package:clock` so tests can
/// fake it.
class DriftCloudSyncRepository implements CloudSyncRepository {
  /// [retryPolicy] controls backoff and the retry cap; [retention] is how
  /// long synced packets are kept locally (7 days by default).
  DriftCloudSyncRepository(
    this._db,
    this._remote, {
    this.retryPolicy = const UploadRetryPolicy(),
    this.retention = const Duration(days: 7),
  });

  final AppDatabase _db;
  final CloudRemote _remote;

  /// Backoff and retry cap per chunk.
  final UploadRetryPolicy retryPolicy;

  /// Age (by chunk start) after which synced chunks are pruned.
  final Duration retention;

  static const _perChunk = AppDatabase.packetsPerChunk;

  @override
  Future<Result<int, Failure>> recoverInterrupted() => _guard(
    () =>
        (_db.update(_db.chunks)
              ..where((c) => c.syncState.equalsValue(ChunkSyncState.uploading)))
            .write(
              const ChunksCompanion(syncState: Value(ChunkSyncState.pending)),
            ),
  );

  @override
  Future<Result<SyncReport, Failure>> uploadEligible({
    bool manual = false,
  }) async {
    if (manual) {
      final reset = await _guard(
        () =>
            (_db.update(
                  _db.chunks,
                )..where((c) => c.syncState.equalsValue(ChunkSyncState.failed)))
                .write(
                  const ChunksCompanion(
                    syncState: Value(ChunkSyncState.pending),
                    attempts: Value(0),
                    nextAttemptAt: Value(null),
                    lastError: Value(null),
                  ),
                ),
      );
      if (reset case Err(:final failure)) return Err(failure);
    }

    final due = await _guard(() => _dueChunks(ignoreBackoff: manual));
    if (due case Err(:final failure)) return Err(failure);
    final work = due.valueOrNull!;
    if (work.isEmpty) {
      return _guard(() async => SyncReport(nextRetryAt: await _nextRetryAt()));
    }

    final signedIn = await _remote.signIn();
    if (signedIn case Err(:final failure)) return Err(failure);
    final uid = signedIn.valueOrNull!;

    var uploaded = 0, retry = 0, failed = 0;
    void count(ChunkSyncState s) => switch (s) {
      ChunkSyncState.synced => uploaded++,
      ChunkSyncState.pending => retry++,
      ChunkSyncState.failed => failed++,
      ChunkSyncState.uploading => null,
    };

    return _guard(() async {
      for (final MapEntry(key: session, value: chunks) in work.entries) {
        // Session document first, so the cloud never holds chunks of an
        // unknown session. `set()` is idempotent; it also publishes endedAt.
        final put = await _remote.putSession(uid, _sessionUpload(session));
        if (put case Err(:final failure)) {
          for (final chunk in chunks) {
            count(await _recordFailure(chunk, failure));
          }
          continue;
        }
        for (final chunk in chunks) {
          count(await _uploadChunk(uid, session, chunk));
        }
      }
      return SyncReport(
        uploaded: uploaded,
        retryScheduled: retry,
        failed: failed,
        nextRetryAt: await _nextRetryAt(),
      );
    });
  }

  /// Eligible chunks grouped by session, in chunk order.
  Future<Map<SessionRow, List<ChunkRow>>> _dueChunks({
    required bool ignoreBackoff,
  }) async {
    final c = _db.chunks, s = _db.sessions;
    final rows =
        await (_db.select(c).join([innerJoin(s, s.id.equalsExp(c.sessionId))])
              ..where(
                c.syncState.equalsValue(ChunkSyncState.pending) &
                    c.prunedAt.isNull() &
                    // Upload eligibility: the chunk can no longer change.
                    (c.packetCount.isBiggerOrEqualValue(_perChunk) |
                        s.endedAt.isNotNull()),
              )
              ..orderBy([
                OrderingTerm.asc(s.startedAt),
                OrderingTerm.asc(c.sessionId),
                OrderingTerm.asc(c.chunkIndex),
              ]))
            .get();
    final now = clock.now();
    final bySession = <String, (SessionRow, List<ChunkRow>)>{};
    for (final row in rows) {
      final chunk = row.readTable(c);
      // Backoff filtered in Dart: timestamps are stored as text, so SQL
      // comparisons across time zones would be unreliable.
      final next = chunk.nextAttemptAt;
      if (!ignoreBackoff && next != null && next.isAfter(now)) continue;
      final session = row.readTable(s);
      (bySession[session.id] ??= (session, [])).$2.add(chunk);
    }
    return {for (final (session, chunks) in bySession.values) session: chunks};
  }

  Future<ChunkSyncState> _uploadChunk(
    String uid,
    SessionRow session,
    ChunkRow chunk,
  ) async {
    await _setState(chunk, ChunkSyncState.uploading);
    final packets =
        await (_db.select(_db.packets)..where(
              (p) =>
                  p.sessionId.equals(chunk.sessionId) &
                  p.sequence.isBetweenValues(
                    chunk.chunkIndex * _perChunk,
                    chunk.chunkIndex * _perChunk + _perChunk - 1,
                  ),
            ))
            .get();
    final ChunkUpload upload;
    try {
      upload = ChunkEncoder.encode(
        session: session,
        chunkIndex: chunk.chunkIndex,
        packets: packets,
      );
    } on ArgumentError catch (e) {
      return _recordFailure(
        chunk,
        CloudFailure('cannot encode chunk: ${e.message}', retryable: false),
      );
    }
    final put = await _remote.putChunk(uid, upload);
    switch (put) {
      case Ok():
        await (_db.update(_db.chunks)..where(
              (c) =>
                  c.sessionId.equals(chunk.sessionId) &
                  c.chunkIndex.equals(chunk.chunkIndex),
            ))
            .write(
              ChunksCompanion(
                syncState: const Value(ChunkSyncState.synced),
                syncedAt: Value(clock.now()),
                nextAttemptAt: const Value(null),
                lastError: const Value(null),
              ),
            );
        return ChunkSyncState.synced;
      case Err(:final failure):
        return _recordFailure(chunk, failure);
    }
  }

  /// Counts a failed attempt: back to `pending` with a backoff deadline,
  /// or `failed` when the cap is reached or the error is permanent.
  Future<ChunkSyncState> _recordFailure(
    ChunkRow chunk,
    CloudFailure failure,
  ) async {
    final attempts = chunk.attempts + 1;
    final giveUp = !failure.retryable || retryPolicy.exhausted(attempts);
    final state = giveUp ? ChunkSyncState.failed : ChunkSyncState.pending;
    await (_db.update(_db.chunks)..where(
          (c) =>
              c.sessionId.equals(chunk.sessionId) &
              c.chunkIndex.equals(chunk.chunkIndex),
        ))
        .write(
          ChunksCompanion(
            syncState: Value(state),
            attempts: Value(attempts),
            nextAttemptAt: Value(
              giveUp ? null : clock.now().add(retryPolicy.delayAfter(attempts)),
            ),
            lastError: Value(failure.message),
          ),
        );
    return state;
  }

  Future<void> _setState(ChunkRow chunk, ChunkSyncState state) =>
      (_db.update(_db.chunks)..where(
            (c) =>
                c.sessionId.equals(chunk.sessionId) &
                c.chunkIndex.equals(chunk.chunkIndex),
          ))
          .write(ChunksCompanion(syncState: Value(state)));

  Future<DateTime?> _nextRetryAt() async {
    final deadlines =
        await (_db.selectOnly(_db.chunks)
              ..addColumns([_db.chunks.nextAttemptAt])
              ..where(
                _db.chunks.syncState.equalsValue(ChunkSyncState.pending) &
                    _db.chunks.nextAttemptAt.isNotNull(),
              ))
            .map((r) => r.read(_db.chunks.nextAttemptAt)!)
            .get();
    if (deadlines.isEmpty) return null;
    return deadlines.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  @override
  Future<Result<int, Failure>> pruneSynced() => _guard(() async {
    final cutoff = clock.now().subtract(retention);
    final candidates =
        await (_db.select(_db.chunks)..where(
              (c) =>
                  c.syncState.equalsValue(ChunkSyncState.synced) &
                  c.prunedAt.isNull(),
            ))
            .get();
    final old = candidates.where((c) => c.startedAt.isBefore(cutoff)).toList();
    if (old.isEmpty) return 0;
    final now = clock.now();
    await _db.transaction(() async {
      for (final chunk in old) {
        await (_db.delete(_db.packets)..where(
              (p) =>
                  p.sessionId.equals(chunk.sessionId) &
                  p.sequence.isBetweenValues(
                    chunk.chunkIndex * _perChunk,
                    chunk.chunkIndex * _perChunk + _perChunk - 1,
                  ),
            ))
            .go();
        await (_db.update(_db.chunks)..where(
              (c) =>
                  c.sessionId.equals(chunk.sessionId) &
                  c.chunkIndex.equals(chunk.chunkIndex),
            ))
            .write(ChunksCompanion(prunedAt: Value(now)));
      }
    });
    return old.length;
  });

  @override
  Stream<SyncCounts> watchCounts() => _db
      .customSelect(
        '''
        SELECT
          COALESCE(SUM(sync_state = 'pending'), 0) AS pending,
          COALESCE(SUM(sync_state = 'uploading'), 0) AS uploading,
          COALESCE(SUM(sync_state = 'synced'), 0) AS synced,
          COALESCE(SUM(sync_state = 'failed'), 0) AS failed,
          COALESCE(SUM(pruned_at IS NOT NULL), 0) AS pruned
        FROM chunks
        ''',
        readsFrom: {_db.chunks},
      )
      .watchSingle()
      .map(
        (r) => SyncCounts(
          pending: r.read<int>('pending'),
          uploading: r.read<int>('uploading'),
          synced: r.read<int>('synced'),
          failed: r.read<int>('failed'),
          pruned: r.read<int>('pruned'),
        ),
      );

  SessionUpload _sessionUpload(SessionRow s) => SessionUpload(
    sessionId: s.id,
    deviceId: s.deviceId,
    startedAt: s.startedAt,
    endedAt: s.endedAt,
    sampleRateHz: s.sampleRateHz,
  );

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on Exception catch (e) {
      return Err(StorageFailure(e.toString()));
    }
  }
}
