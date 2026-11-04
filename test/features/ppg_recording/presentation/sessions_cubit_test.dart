import 'dart:async';

import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/domain/entities/session.dart';
import 'package:ble_prototype/features/ppg_recording/domain/recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/cubit/sessions_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/packets.dart';
import '../../../helpers/test_database.dart';

class _MockRecordingRepository extends Mock implements RecordingRepository {}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  group('with a mocked repository', () {
    late _MockRecordingRepository repo;
    late StreamController<List<SessionSummary>> sessions;
    final summary = SessionSummary(
      session: Session(
        id: 's',
        deviceId: 'dev',
        startedAt: t0,
        sampleRateHz: 50,
      ),
      packetCount: 1,
      historyPacketCount: 0,
      firstSequence: 0,
      lastSequence: 0,
      chunkCount: 1,
      pendingChunks: 1,
      uploadingChunks: 0,
      syncedChunks: 0,
      failedChunks: 0,
    );

    setUp(() {
      repo = _MockRecordingRepository();
      sessions = StreamController<List<SessionSummary>>();
      when(() => repo.watchSessions()).thenAnswer((_) => sessions.stream);
    });

    tearDown(() => sessions.close());

    test('starts loading', () {
      expect(SessionsCubit(repo).state, const SessionsState());
      expect(const SessionsState().loading, isTrue);
    });

    blocTest<SessionsCubit, SessionsState>(
      'mirrors every DB snapshot',
      build: () => SessionsCubit(repo),
      act: (_) async {
        sessions.add(const []);
        await Future<void>.delayed(Duration.zero);
        sessions.add([summary]);
      },
      expect: () => [
        const SessionsState(loading: false),
        SessionsState(sessions: [summary], loading: false),
      ],
    );

    blocTest<SessionsCubit, SessionsState>(
      'stream errors are reported, not thrown',
      build: () => SessionsCubit(repo),
      act: (_) => sessions.addError(Exception('db')),
      errors: () => [isA<Exception>()],
      expect: () => const <SessionsState>[],
    );
  });

  group('with a Drift in-memory database', () {
    late AppDatabase db;
    late DriftRecordingRepository repo;

    setUp(() {
      db = testDatabase();
      repo = DriftRecordingRepository(db);
    });

    tearDown(() => db.close());

    test('reflects sessions written to the database', () async {
      final cubit = SessionsCubit(repo);
      await expectLater(
        cubit.stream,
        emits(const SessionsState(loading: false)),
      );

      final id = (await repo.startSession(
        deviceId: 'dev',
        startedAt: t0,
      )).valueOrNull!.id;
      await repo.savePackets(id, packets(0, 4));

      await expectLater(
        cubit.stream,
        emitsThrough(
          isA<SessionsState>().having(
            (s) => s.sessions.singleOrNull?.packetCount,
            'packetCount',
            5,
          ),
        ),
      );
      await cubit.close();
    });
  });
}
