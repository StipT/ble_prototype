// End-to-end check of the cloud upload against the Firebase emulator suite:
// Drift → DriftCloudSyncRepository → chunk encoder → Firestore emulator
// (security rules) → analyzeChunkOnCreate trigger → metrics document.
//
// Not part of `flutter test` (it lives outside test/). Run from functions/:
//
//   PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH npm run test:flutter-e2e
//
// which starts auth + firestore + functions emulators and runs
// `flutter test --no-pub test_emulator` inside `firebase emulators:exec`.
import 'dart:io';
import 'dart:math' as math;

import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/features/cloud_sync/data/chunk_encoder.dart';
import 'package:ble_prototype/features/cloud_sync/data/drift_cloud_sync_repository.dart';
import 'package:ble_prototype/features/cloud_sync/domain/entities/sync_counts.dart';
import 'package:ble_prototype/features/device_connection/data/fake/ppg_signal_generator.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/test_database.dart';
import 'rest_firestore_remote.dart';

void main() {
  final firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];

  late AppDatabase db;
  late RestFirestoreRemote remote;
  late DriftRecordingRepository recording;
  late DriftCloudSyncRepository sync;

  setUp(() {
    if (firestoreHost == null || authHost == null) {
      fail(
        'FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST not set. Run '
        'via `npm run test:flutter-e2e` in functions/.',
      );
    }
    db = testDatabase();
    remote = RestFirestoreRemote(
      firestoreHost: firestoreHost,
      authHost: authHost,
    );
    recording = DriftRecordingRepository(db);
    sync = DriftCloudSyncRepository(db, remote);
  });

  tearDown(() async {
    remote.close();
    await db.close();
  });

  /// Polls the metrics doc written by the Cloud Function.
  Future<Map<String, dynamic>> metrics(String uid, String sid, int i) async {
    final path = 'users/$uid/sessions/$sid/metrics/${sid}_$i';
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final doc = await remote.getDocument(path);
      if (doc != null) return doc['fields'] as Map<String, dynamic>;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('metrics $path not written within 30 s');
  }

  num number(Map<String, dynamic> v) =>
      v['doubleValue'] as num? ?? int.parse(v['integerValue'] as String);

  test('uploaded chunks pass the rules and get analyzed', () async {
    // 25 s at 72 bpm; packet 140 lost for good (never in the backlog).
    final generator = PpgSignalGenerator(random: math.Random(7));
    final start = DateTime.utc(2026, 1, 1, 8);
    final all = [
      for (var seq = 0; seq < 250; seq++)
        PpgPacket(
          sequence: seq,
          timestamp: start.add(Duration(milliseconds: 100 * seq)),
          samples: generator.next(5),
          kind: PpgPacketKind.live,
        ),
    ];
    final session = (await recording.startSession(
      deviceId: 'FA:KE:00:00:00:01',
      startedAt: start,
    )).valueOrNull!;
    await recording.savePackets(session.id, [
      for (final p in all)
        if (p.sequence != 140) p,
    ]);
    await recording.endSession(
      session.id,
      start.add(const Duration(seconds: 25)),
    );

    final report = await sync.uploadEligible();
    expect(report.failureOrNull, isNull);
    expect(report.valueOrNull!.uploaded, 3);
    expect(
      await sync.watchCounts().first,
      const SyncCounts(synced: 3),
      reason: 'all three chunks accepted by firestore.rules',
    );

    final uid = (await remote.signIn()).valueOrNull!;
    final sessionDoc = await remote.getDocument(
      'users/$uid/sessions/${session.id}',
    );
    expect(sessionDoc!['fields']['endedAt']['timestampValue'], isNotNull);

    final chunk1 = (await remote.getDocument(
      'users/$uid/sessions/${session.id}/chunks/${session.id}_1',
    ))!['fields'];
    expect(chunk1['packetCount'], {'integerValue': '99'});
    expect(chunk1['missingSequences']['arrayValue']['values'], [
      {'integerValue': '140'},
    ]);
    expect(chunk1['encoding'], {'stringValue': 'gzip-u24le'});

    for (final i in [0, 1, 2]) {
      final m = await metrics(uid, session.id, i);
      expect(m['status'], {'stringValue': 'ok'}, reason: 'chunk $i: $m');
      expect(number(m['chunkIndex']), i);
      final hr = number(m['avgHeartRateBpm']);
      expect(hr, closeTo(72, 3), reason: 'chunk $i heart rate');
    }
    final m1 = await metrics(uid, session.id, 1);
    expect(number(m1['signalQuality']['mapValue']['fields']['coverage']), 0.99);

    // Crash after the write but before `synced` was stored: the retry
    // rewrites the identical document, which the append-only rules allow.
    await (db.update(
      db.chunks,
    )).write(const ChunksCompanion(syncState: Value(ChunkSyncState.uploading)));
    await sync.recoverInterrupted();
    final retry = await sync.uploadEligible();
    expect(retry.valueOrNull!.uploaded, 3);

    // A *changed* chunk is rejected: the cloud copy is append-only.
    final packets =
        await (db.select(db.packets)..where(
              (p) =>
                  p.sessionId.equals(session.id) &
                  p.sequence.isBetweenValues(0, 99),
            ))
            .get();
    final sessionRow = await (db.select(
      db.sessions,
    )..where((s) => s.id.equals(session.id))).getSingle();
    final changed = await remote.putChunk(
      uid,
      ChunkEncoder.encode(
        session: sessionRow,
        chunkIndex: 0,
        packets: packets.skip(1).toList(),
      ),
    );
    expect(changed.failureOrNull, isA<CloudFailure>());
    expect(changed.failureOrNull!.retryable, isFalse);
    expect(changed.failureOrNull!.message, contains('PERMISSION_DENIED'));
  });
}
