import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/features/cloud_sync/data/drift_cloud_sync_repository.dart';
import 'package:ble_prototype/features/cloud_sync/domain/entities/sync_counts.dart';
import 'package:ble_prototype/features/cloud_sync/domain/upload_retry_policy.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_cloud_remote.dart';
import '../../../helpers/packets.dart';
import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DriftRecordingRepository recording;
  late FakeCloudRemote remote;
  late DriftCloudSyncRepository repo;
  // Packets from helpers are stamped 2026-01-01 UTC.
  var now = DateTime.utc(2026, 1, 2);
  final testClock = Clock(() => now);

  const policy = UploadRetryPolicy(
    initialDelay: Duration(seconds: 10),
    maxDelay: Duration(seconds: 25),
    maxAttempts: 3,
  );

  setUp(() {
    now = DateTime.utc(2026, 1, 2);
    db = testDatabase();
    recording = DriftRecordingRepository(db);
    remote = FakeCloudRemote();
    repo = DriftCloudSyncRepository(db, remote, retryPolicy: policy);
  });
  tearDown(() => db.close());

  Future<T> at<T>(Future<T> Function() body) => withClock(testClock, body);

  Future<String> session({required int from, required int to}) async {
    final s = (await recording.startSession(
      deviceId: 'fake-ppg-01',
      startedAt: DateTime.utc(2026),
    )).valueOrNull!;
    await recording.savePackets(s.id, packets(from, to));
    return s.id;
  }

  Future<ChunkRow> chunk(String sessionId, int index) =>
      (db.select(db.chunks)..where(
            (c) => c.sessionId.equals(sessionId) & c.chunkIndex.equals(index),
          ))
          .getSingle();

  Future<int> packetCount(String sessionId) async => (await (db.select(
    db.packets,
  )..where((p) => p.sessionId.equals(sessionId))).get()).length;

  group('eligibility', () {
    test('active session: only full chunks are uploaded', () async {
      final id = await session(from: 0, to: 149); // chunk 0 full, 1 partial
      final r = await at(repo.uploadEligible);

      expect(r.valueOrNull, const SyncReport(uploaded: 1));
      expect(remote.calls, ['signIn', 'session:$id', 'chunk:${id}_0']);
      expect((await chunk(id, 0)).syncState, ChunkSyncState.synced);
      expect((await chunk(id, 0)).syncedAt, now);
      expect((await chunk(id, 1)).syncState, ChunkSyncState.pending);
      expect(remote.sessions['test-uid/$id']!.endedAt, isNull);
    });

    test('ended session: the partial chunk becomes eligible', () async {
      final id = await session(from: 0, to: 149);
      await at(repo.uploadEligible);
      await recording.endSession(id, DateTime.utc(2026, 1, 1, 1));
      remote.calls.clear();

      final r = await at(repo.uploadEligible);
      expect(r.valueOrNull, const SyncReport(uploaded: 1));
      expect(remote.calls, ['signIn', 'session:$id', 'chunk:${id}_1']);
      final doc = remote.chunks['test-uid/${id}_1']!;
      expect(doc.firstSequence, 100);
      expect(doc.lastSequence, 149);
      expect(doc.packetCount, 50);
      expect(
        remote.sessions['test-uid/$id']!.endedAt,
        DateTime.utc(2026, 1, 1, 1),
      );
    });

    test('nothing due: no sign-in, empty report', () async {
      await session(from: 0, to: 10);
      final r = await at(repo.uploadEligible);
      expect(r.valueOrNull, const SyncReport());
      expect(remote.calls, isEmpty);
    });

    test('sign-in failure leaves chunks untouched', () async {
      final id = await session(from: 0, to: 99);
      remote.signInFailure = const CloudFailure('offline');
      final r = await at(repo.uploadEligible);
      expect(r.failureOrNull, const CloudFailure('offline'));
      final c = await chunk(id, 0);
      expect(c.syncState, ChunkSyncState.pending);
      expect(c.attempts, 0);
    });
  });

  group('backoff and retry cap', () {
    test('transient failures back off exponentially, then fail', () async {
      final id = await session(from: 0, to: 99);
      remote.alwaysFailChunks = const CloudFailure('unavailable');

      var r = await at(repo.uploadEligible);
      var c = await chunk(id, 0);
      expect(r.valueOrNull!.retryScheduled, 1);
      expect(c.syncState, ChunkSyncState.pending);
      expect(c.attempts, 1);
      expect(c.lastError, 'unavailable');
      expect(c.nextAttemptAt, now.add(const Duration(seconds: 10)));
      expect(r.valueOrNull!.nextRetryAt, c.nextAttemptAt);

      // Not due yet: nothing is attempted.
      now = now.add(const Duration(seconds: 9));
      remote.calls.clear();
      r = await at(repo.uploadEligible);
      expect(remote.calls, isEmpty);
      expect(r.valueOrNull!.nextRetryAt, c.nextAttemptAt);

      now = now.add(const Duration(seconds: 1));
      await at(repo.uploadEligible);
      c = await chunk(id, 0);
      expect(c.attempts, 2);
      expect(c.nextAttemptAt, now.add(const Duration(seconds: 20)));

      now = c.nextAttemptAt!;
      r = await at(repo.uploadEligible);
      c = await chunk(id, 0);
      expect(r.valueOrNull, const SyncReport(failed: 1));
      expect(c.syncState, ChunkSyncState.failed);
      expect(c.attempts, 3);
      expect(c.nextAttemptAt, isNull);

      // Failed chunks are not retried automatically, even much later.
      now = now.add(const Duration(days: 1));
      remote.calls.clear();
      await at(repo.uploadEligible);
      expect(remote.calls, isEmpty);
    });

    test('manual sync resets failed chunks and ignores backoff', () async {
      final id = await session(from: 0, to: 199);
      remote.chunkFailures.add(
        const CloudFailure('denied', retryable: false),
      ); // chunk 0 → failed
      remote.chunkFailures.add(
        const CloudFailure('flaky'),
      ); // chunk 1 → backoff
      await at(repo.uploadEligible);
      expect((await chunk(id, 0)).syncState, ChunkSyncState.failed);
      expect((await chunk(id, 0)).attempts, 1, reason: 'permanent: no retry');
      expect((await chunk(id, 1)).syncState, ChunkSyncState.pending);

      final r = await at(() => repo.uploadEligible(manual: true));
      expect(r.valueOrNull, const SyncReport(uploaded: 2));
      final c0 = await chunk(id, 0);
      expect(c0.syncState, ChunkSyncState.synced);
      expect(c0.attempts, 0);
      expect(c0.lastError, isNull);
    });

    test('session doc failure counts as an attempt for its chunks', () async {
      final id = await session(from: 0, to: 99);
      remote.sessionFailure = const CloudFailure('unavailable');
      final r = await at(repo.uploadEligible);
      expect(r.valueOrNull!.retryScheduled, 1);
      expect(remote.calls, ['signIn', 'session:$id']);
      expect((await chunk(id, 0)).attempts, 1);
    });
  });

  group('crash safety and idempotency', () {
    test('recoverInterrupted resets uploading chunks to pending', () async {
      final id = await session(from: 0, to: 99);
      await (db.update(db.chunks)).write(
        const ChunksCompanion(syncState: Value(ChunkSyncState.uploading)),
      );
      expect((await repo.recoverInterrupted()).valueOrNull, 1);
      expect((await chunk(id, 0)).syncState, ChunkSyncState.pending);
    });

    test('re-upload after a crash writes the identical document', () async {
      final id = await session(from: 0, to: 99);
      await at(repo.uploadEligible);
      final first = remote.chunks['test-uid/${id}_0'];
      // App died after the write but before marking the chunk synced.
      await (db.update(db.chunks)).write(
        const ChunksCompanion(syncState: Value(ChunkSyncState.uploading)),
      );
      await repo.recoverInterrupted();

      final r = await at(repo.uploadEligible);
      expect(r.valueOrNull, const SyncReport(uploaded: 1));
      expect(remote.chunks['test-uid/${id}_0'], first);
    });
  });

  group('pruning', () {
    test('only synced chunks older than the retention are pruned', () async {
      final id = await session(from: 0, to: 249);
      await recording.endSession(id, DateTime.utc(2026, 1, 1, 1));
      remote.chunkFailures.add(const CloudFailure('x', retryable: false));
      await at(repo.uploadEligible); // 0 failed, 1 and 2 synced
      expect(await packetCount(id), 250);

      now = DateTime.utc(2026, 1, 7, 23);
      expect((await at(repo.pruneSynced)).valueOrNull, 0, reason: '< 7 days');

      now = DateTime.utc(2026, 1, 8, 1);
      expect((await at(repo.pruneSynced)).valueOrNull, 2);
      expect(await packetCount(id), 100, reason: 'failed chunk 0 kept');
      final c1 = await chunk(id, 1);
      expect(c1.prunedAt, now);
      expect(c1.syncState, ChunkSyncState.synced);
      expect(c1.packetCount, 100, reason: 'tombstone keeps aggregates');
      expect((await at(repo.pruneSynced)).valueOrNull, 0);

      // Pruned chunks are never uploaded again, not even manually.
      remote.calls.clear();
      await at(() => repo.uploadEligible(manual: true));
      expect(remote.calls, ['signIn', 'session:$id', 'chunk:${id}_0']);
    });

    test('retention is configurable', () async {
      repo = DriftCloudSyncRepository(
        db,
        remote,
        retention: const Duration(hours: 12),
      );
      final id = await session(from: 0, to: 99);
      await at(repo.uploadEligible);
      now = DateTime.utc(2026, 1, 1, 13);
      expect((await at(repo.pruneSynced)).valueOrNull, 1);
      expect(await packetCount(id), 0);
    });
  });

  test('watchCounts reports chunk states', () async {
    final id = await session(from: 0, to: 349);
    await recording.endSession(id, DateTime.utc(2026, 1, 1, 1));
    remote.chunkFailures
      ..add(const CloudFailure('x', retryable: false))
      ..add(const CloudFailure('y'));
    await at(repo.uploadEligible);
    now = DateTime.utc(2026, 2);
    await at(repo.pruneSynced);
    expect(
      await repo.watchCounts().first,
      const SyncCounts(pending: 1, synced: 2, failed: 1, pruned: 2),
    );
  });
}
