import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/database/sample_packing.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/domain/entities/sequence_range.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/packets.dart';
import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DriftRecordingRepository repo;
  late TransactionCounter tx;
  final t0 = DateTime.utc(2026, 1, 1);

  setUp(() {
    tx = TransactionCounter();
    db = testDatabase(counter: tx);
    repo = DriftRecordingRepository(db);
  });

  tearDown(() => db.close());

  Future<String> start() async =>
      (await repo.startSession(deviceId: 'dev', startedAt: t0)).valueOrNull!.id;

  Future<List<int>> storedSequences(String sessionId) async =>
      (await (db.select(db.packets)
                ..where((p) => p.sessionId.equals(sessionId))
                ..orderBy([(p) => OrderingTerm.asc(p.sequence)]))
              .get())
          .map((r) => r.sequence)
          .toList();

  test('startSession / activeSession / endSession', () async {
    final id = await start();
    expect((await repo.activeSession()).valueOrNull?.id, id);
    expect(
      (await repo.endSession(id, t0.add(const Duration(minutes: 1)))).isOk,
      isTrue,
    );
    expect((await repo.activeSession()).valueOrNull, isNull);
  });

  test('savePackets stores samples losslessly in one transaction', () async {
    final id = await start();
    final before = tx.count;
    final r = await repo.savePackets(id, packets(0, 49));
    expect(r.valueOrNull, 50);
    expect(tx.count - before, 1);
    final row = await (db.select(
      db.packets,
    )..where((p) => p.sequence.equals(7))).getSingle();
    expect(SamplePacking.unpack(row.samples), packet(7).samples);
    expect(row.timestamp.isAtSameMomentAs(packet(7).timestamp), isTrue);
  });

  test(
    'duplicates (live + history copy, or within a batch) are ignored',
    () async {
      final id = await start();
      await repo.savePackets(id, packets(0, 9));
      final r = await repo.savePackets(id, [
        ...packets(5, 14, kind: PpgPacketKind.history),
        packet(14),
      ]);
      expect(r.valueOrNull, 5);
      expect(await storedSequences(id), List.generate(15, (i) => i));
    },
  );

  test('chunk aggregates follow packets across chunk boundaries', () async {
    final id = await start();
    // Out of order, spanning chunks 0..2 (100 packets per chunk).
    await repo.savePackets(id, packets(150, 210));
    await repo.savePackets(id, packets(90, 120));
    await repo.savePackets(id, packets(121, 149)); // fills chunk 1 fully
    final chunks = await (db.select(
      db.chunks,
    )..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)])).get();
    expect(chunks.map((c) => c.chunkIndex), [0, 1, 2]);
    expect(chunks.map((c) => c.packetCount), [10, 100, 11]);
    expect(chunks[1].firstSequence, 100);
    expect(chunks[1].lastSequence, 199);
    expect(chunks[1].startedAt.isAtSameMomentAs(packet(100).timestamp), isTrue);
    expect(chunks.every((c) => c.syncState == ChunkSyncState.pending), isTrue);
  });

  test('watchSessions emits aggregates and reacts to writes', () async {
    final id = await start();
    final stream = repo.watchSessions();
    expect((await stream.first).single.packetCount, 0);

    await repo.savePackets(id, packets(0, 9));
    await repo.savePackets(id, packets(12, 14, kind: PpgPacketKind.history));
    final s = (await stream.first).single;
    expect(s.session.id, id);
    expect(s.packetCount, 13);
    expect(s.historyPacketCount, 3);
    expect(s.missingPackets, 2);
    expect(s.chunkCount, 1);
    expect(s.pendingChunks, 1);
  });

  test('chunks carry syncState and summaries count each state', () async {
    final id = await start();
    await repo.savePackets(id, packets(0, 399)); // chunks 0..3
    for (final (index, state) in [
      (1, ChunkSyncState.uploading),
      (2, ChunkSyncState.synced),
      (3, ChunkSyncState.failed),
    ]) {
      await (db.update(db.chunks)..where((c) => c.chunkIndex.equals(index)))
          .write(ChunksCompanion(syncState: Value(state)));
    }
    final stored = await (db.select(
      db.chunks,
    )..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)])).get();
    expect(stored.map((c) => c.syncState), ChunkSyncState.values);

    final s = (await repo.watchSessions().first).single;
    expect(s.chunkCount, 4);
    expect(s.pendingChunks, 1);
    expect(s.uploadingChunks, 1);
    expect(s.syncedChunks, 1);
    expect(s.failedChunks, 1);
  });

  test('sessions are listed newest first', () async {
    await repo.startSession(deviceId: 'a', startedAt: t0);
    await repo.startSession(
      deviceId: 'b',
      startedAt: t0.add(const Duration(hours: 1)),
    );
    final list = await repo.watchSessions().first;
    expect(list.map((s) => s.session.deviceId), ['b', 'a']);
  });

  group('missingRanges', () {
    Future<List<SequenceRange>> missing(
      String id, {
      int notBefore = 0,
      required int upTo,
    }) async => (await repo.missingRanges(
      id,
      notBefore: notBefore,
      upTo: upTo,
    )).valueOrNull!;

    test('empty session has no known start: nothing missing', () async {
      final id = await start();
      expect(await missing(id, upTo: 500), isEmpty);
    });

    test('contiguous data up to the device latest: nothing missing', () async {
      final id = await start();
      await repo.savePackets(id, packets(10, 59));
      expect(await missing(id, upTo: 59), isEmpty);
      // A stale (older) latestSequence must not produce a reversed range.
      expect(await missing(id, upTo: 40), isEmpty);
    });

    test('reports inner gaps and the tail, oldest first', () async {
      final id = await start();
      await repo.savePackets(id, [
        ...packets(10, 19),
        ...packets(25, 29),
        packet(31),
        ...packets(40, 49),
      ]);
      expect(await missing(id, upTo: 60), const [
        SequenceRange(20, 24),
        SequenceRange(30, 30),
        SequenceRange(32, 39),
        SequenceRange(50, 60),
      ]);
    });

    test('clips to the device backlog (ring buffer)', () async {
      final id = await start();
      await repo.savePackets(id, [
        ...packets(0, 9),
        ...packets(20, 29),
        ...packets(40, 49),
      ]);
      // Backlog only holds 25..55: 10..19 is gone for good, 30..39 is
      // fetchable, the tail stops at 55.
      expect(await missing(id, notBefore: 25, upTo: 55), const [
        SequenceRange(30, 39),
        SequenceRange(50, 55),
      ]);
      expect(await missing(id, notBefore: 36, upTo: 38), const [
        SequenceRange(36, 38),
      ]);
    });

    test('only looks at the given session', () async {
      final a = await start();
      final b = await start();
      await repo.savePackets(a, [...packets(0, 4), ...packets(8, 9)]);
      await repo.savePackets(b, packets(5, 7));
      expect(await missing(a, upTo: 9), const [SequenceRange(5, 7)]);
      expect(await missing(b, upTo: 9), const [SequenceRange(8, 9)]);
    });
  });

  test('SequenceRange split and clamp', () {
    expect(const SequenceRange(0, 6).split(3), const [
      SequenceRange(0, 2),
      SequenceRange(3, 5),
      SequenceRange(6, 6),
    ]);
    expect(const SequenceRange(0, 6).length, 7);
    expect(const SequenceRange(5, 9).clamp(0, 4), isNull);
    expect(const SequenceRange(5, 9).clamp(7, 20), const SequenceRange(7, 9));
  });
}
