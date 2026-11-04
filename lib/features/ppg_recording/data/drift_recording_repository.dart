import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sample_packing.dart';
import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../../../core/util/ids.dart';
import '../../device_connection/domain/entities/ppg_packet.dart';
import '../domain/entities/sequence_range.dart';
import '../domain/entities/session.dart';
import '../domain/recording_repository.dart';

/// Drift-backed [RecordingRepository].
class DriftRecordingRepository implements RecordingRepository {
  /// Uses [db]; [sampleRateHz] is stamped on new sessions.
  DriftRecordingRepository(this._db, {this.sampleRateHz = 50});

  final AppDatabase _db;

  /// Sample rate recorded on new sessions.
  final int sampleRateHz;

  static const _perChunk = AppDatabase.packetsPerChunk;

  @override
  Future<Result<Session, Failure>> startSession({
    required String deviceId,
    required DateTime startedAt,
  }) => _guard(() async {
    final session = Session(
      id: newId(),
      deviceId: deviceId,
      startedAt: startedAt,
      sampleRateHz: sampleRateHz,
    );
    await _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: session.id,
            deviceId: deviceId,
            startedAt: startedAt,
            sampleRateHz: sampleRateHz,
          ),
        );
    return session;
  });

  @override
  Future<Result<void, Failure>> endSession(
    String sessionId,
    DateTime endedAt,
  ) => _guard(() async {
    await (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(endedAt: Value(endedAt)));
  });

  @override
  Future<Result<int, Failure>> savePackets(
    String sessionId,
    List<PpgPacket> packets,
  ) => _guard(() {
    if (packets.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      // Keep only sequences not stored yet (and de-duplicate within batch).
      final bySeq = {for (final p in packets) p.sequence: p};
      final existing =
          await (_db.selectOnly(_db.packets)
                ..addColumns([_db.packets.sequence])
                ..where(
                  _db.packets.sessionId.equals(sessionId) &
                      _db.packets.sequence.isIn(bySeq.keys),
                ))
              .map((r) => r.read(_db.packets.sequence)!)
              .get();
      existing.forEach(bySeq.remove);
      if (bySeq.isEmpty) return 0;

      final fresh = bySeq.values.toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      await _db.batch((b) {
        b.insertAll(_db.packets, [
          for (final p in fresh)
            PacketsCompanion.insert(
              sessionId: sessionId,
              sequence: p.sequence,
              timestamp: p.timestamp,
              samples: SamplePacking.pack(p.samples),
              fromHistory: Value(p.kind == PpgPacketKind.history),
            ),
        ]);
      });

      // Merge per-chunk aggregates.
      final groups = <int, List<PpgPacket>>{};
      for (final p in fresh) {
        (groups[p.sequence ~/ _perChunk] ??= []).add(p);
      }
      for (final MapEntry(key: index, value: group) in groups.entries) {
        await _upsertChunk(sessionId, index, group);
      }
      return fresh.length;
    });
  });

  Future<void> _upsertChunk(
    String sessionId,
    int index,
    List<PpgPacket> sortedGroup,
  ) => _db.customInsert(
    '''
    INSERT INTO chunks
      (session_id, chunk_index, packet_count, first_sequence, last_sequence,
       started_at, sync_state, attempts)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', 0)
    ON CONFLICT (session_id, chunk_index) DO UPDATE SET
      packet_count = packet_count + excluded.packet_count,
      started_at = CASE WHEN excluded.first_sequence < first_sequence
                   THEN excluded.started_at ELSE started_at END,
      first_sequence = MIN(first_sequence, excluded.first_sequence),
      last_sequence = MAX(last_sequence, excluded.last_sequence)
    ''',
    variables: [
      Variable.withString(sessionId),
      Variable.withInt(index),
      Variable.withInt(sortedGroup.length),
      Variable.withInt(sortedGroup.first.sequence),
      Variable.withInt(sortedGroup.last.sequence),
      Variable.withDateTime(sortedGroup.first.timestamp),
    ],
    updates: {_db.chunks},
  );

  @override
  Future<Result<List<SequenceRange>, Failure>> missingRanges(
    String sessionId, {
    required int notBefore,
    required int upTo,
  }) => _guard(() async {
    // One row per stored packet whose successor is missing: the hole starts
    // right after it and ends just before the next stored packet (NULL for
    // the newest packet = the open-ended tail). Both lookups hit the
    // (session_id, sequence) primary-key index, so the cost grows with the
    // number of holes, not with the number of packets.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.sequence + 1 AS gap_from,
            (SELECT MIN(q.sequence) FROM packets q
               WHERE q.session_id = p.session_id
                 AND q.sequence > p.sequence) - 1 AS gap_to
          FROM packets p
          WHERE p.session_id = ?1
            AND NOT EXISTS (SELECT 1 FROM packets n
               WHERE n.session_id = p.session_id
                 AND n.sequence = p.sequence + 1)
          ORDER BY p.sequence
          ''',
          variables: [Variable.withString(sessionId)],
          readsFrom: {_db.packets},
        )
        .get();
    final ranges = <SequenceRange>[];
    for (final r in rows) {
      final from = r.read<int>('gap_from');
      final to = r.readNullable<int>('gap_to') ?? upTo;
      if (from > to) continue; // tail already covered (upTo is stale)
      if (SequenceRange(from, to).clamp(notBefore, upTo) case final range?) {
        ranges.add(range);
      }
    }
    return ranges;
  });

  @override
  Future<Result<Session?, Failure>> activeSession() => _guard(() async {
    final row =
        await (_db.select(_db.sessions)
              ..where((s) => s.endedAt.isNull())
              ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toSession(row);
  });

  @override
  Stream<List<SessionSummary>> watchSessions() => _db
      .customSelect(
        '''
        SELECT s.*,
          COALESCE(SUM(c.packet_count), 0) AS packet_count,
          MIN(c.first_sequence) AS first_seq,
          MAX(c.last_sequence) AS last_seq,
          COUNT(c.chunk_index) AS chunk_count,
          COALESCE(SUM(c.sync_state = 'pending'), 0) AS pending,
          COALESCE(SUM(c.sync_state = 'uploading'), 0) AS uploading,
          COALESCE(SUM(c.sync_state = 'synced'), 0) AS synced,
          COALESCE(SUM(c.sync_state = 'failed'), 0) AS failed,
          (SELECT COUNT(*) FROM packets p
             WHERE p.session_id = s.id AND p.from_history = 1) AS history
        FROM sessions s
        LEFT JOIN chunks c ON c.session_id = s.id
        GROUP BY s.id
        ''',
        readsFrom: {_db.sessions, _db.chunks, _db.packets},
      )
      .watch()
      .map(
        (rows) =>
            rows
                .map(
                  (r) => SessionSummary(
                    session: _toSession(_db.sessions.map(r.data)),
                    packetCount: r.read<int>('packet_count'),
                    historyPacketCount: r.read<int>('history'),
                    firstSequence: r.readNullable<int>('first_seq'),
                    lastSequence: r.readNullable<int>('last_seq'),
                    chunkCount: r.read<int>('chunk_count'),
                    pendingChunks: r.read<int>('pending'),
                    uploadingChunks: r.read<int>('uploading'),
                    syncedChunks: r.read<int>('synced'),
                    failedChunks: r.read<int>('failed'),
                  ),
                )
                .toList()
              ..sort(
                (a, b) => b.session.startedAt.compareTo(a.session.startedAt),
              ),
      );

  Session _toSession(SessionRow row) => Session(
    id: row.id,
    deviceId: row.deviceId,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    sampleRateHz: row.sampleRateHz,
  );

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on Exception catch (e) {
      return Err(StorageFailure(e.toString()));
    }
  }
}
