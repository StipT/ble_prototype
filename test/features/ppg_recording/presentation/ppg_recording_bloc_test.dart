import 'dart:async';

import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/device_connection/domain/device_repository.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/domain/entities/session.dart';
import 'package:ble_prototype/features/ppg_recording/domain/recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/bloc/ppg_recording_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/packets.dart';
import '../../../helpers/test_database.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockRecordingRepository extends Mock implements RecordingRepository {}

void main() {
  late _MockDeviceRepository device;
  late StreamController<PpgPacket> live;
  late AppDatabase db;
  late TransactionCounter tx;
  late DriftRecordingRepository recording;

  setUp(() {
    device = _MockDeviceRepository();
    live = StreamController<PpgPacket>.broadcast();
    when(() => device.livePackets).thenAnswer((_) => live.stream);
    tx = TransactionCounter();
    db = testDatabase(counter: tx);
    recording = DriftRecordingRepository(db);
  });

  tearDown(() async {
    await live.close();
    await db.close();
  });

  Future<List<int>> stored() async =>
      (await (db.select(
            db.packets,
          )..orderBy([(p) => OrderingTerm.asc(p.sequence)])).get())
          .map((r) => r.sequence)
          .toList();

  PpgRecordingBloc build() =>
      PpgRecordingBloc(device: device, recording: recording);

  Future<void> tick([int ms = 0]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  blocTest<PpgRecordingBloc, PpgRecordingState>(
    'writes 50-packet batches, then flushes the remainder after 250 ms',
    build: build,
    act: (bloc) async {
      bloc.add(const RecordingStarted('dev'));
      await tick(10);
      packets(0, 119).forEach(live.add);
      await tick(400);
    },
    expect: () => [
      isA<RecordingActive>().having((s) => s.savedPackets, 'saved', 0),
      isA<RecordingActive>()
          .having((s) => s.savedPackets, 'saved', 50)
          .having((s) => s.batchesWritten, 'batches', 1),
      isA<RecordingActive>().having((s) => s.savedPackets, 'saved', 100),
      isA<RecordingActive>()
          .having((s) => s.savedPackets, 'saved', 120)
          .having((s) => s.batchesWritten, 'batches', 3)
          .having((s) => s.lastSequence, 'last', 119),
    ],
    verify: (_) async {
      expect(await stored(), List.generate(120, (i) => i));
      // startSession is a single insert (implicit tx); 3 batch transactions.
      expect(tx.count, 3);
    },
  );

  blocTest<PpgRecordingBloc, PpgRecordingState>(
    'stop flushes the partial batch: no loss across batch boundaries',
    build: build,
    act: (bloc) async {
      bloc.add(const RecordingStarted('dev'));
      await tick(10);
      // Bursts that straddle the 50-packet boundary and timer flushes.
      packets(0, 34).forEach(live.add);
      await tick(300);
      packets(35, 77).forEach(live.add);
      await tick(5);
      packets(78, 80).forEach(live.add);
      bloc.add(const RecordingStopped()); // 31 packets still buffered
      await tick(50);
      packets(81, 90).forEach(live.add); // after stop: must be ignored
      await tick(300);
    },
    skip: 1,
    verify: (bloc) async {
      expect(await stored(), List.generate(81, (i) => i));
      final state = bloc.state as RecordingIdle;
      expect(state.lastSession?.endedAt, isNotNull);
      final sessions = await recording.watchSessions().first;
      expect(sessions.single.session.isActive, isFalse);
      expect(sessions.single.packetCount, 81);
    },
  );

  blocTest<PpgRecordingBloc, PpgRecordingState>(
    'packets before Record are not persisted',
    build: build,
    act: (bloc) async {
      packets(0, 9).forEach(live.add);
      await tick(300);
      bloc.add(const RecordingStarted('dev'));
      await tick(10);
      packets(10, 12).forEach(live.add);
      bloc.add(const RecordingStopped());
      await tick(50);
    },
    verify: (_) async => expect(await stored(), [10, 11, 12]),
  );

  blocTest<PpgRecordingBloc, PpgRecordingState>(
    'second Record while active is ignored',
    build: build,
    act: (bloc) async {
      bloc
        ..add(const RecordingStarted('dev'))
        ..add(const RecordingStarted('dev'));
      await tick(10);
    },
    expect: () => [isA<RecordingActive>()],
  );

  group('with failing storage', () {
    late _MockRecordingRepository failing;
    final session = Session(
      id: 's',
      deviceId: 'dev',
      startedAt: DateTime(2026),
      sampleRateHz: 50,
    );

    setUp(() {
      failing = _MockRecordingRepository();
      registerFallbackValue(<PpgPacket>[]);
    });

    blocTest<PpgRecordingBloc, PpgRecordingState>(
      'start failure returns to idle with the failure',
      build: () => PpgRecordingBloc(device: device, recording: failing),
      setUp: () => when(
        () => failing.startSession(
          deviceId: any(named: 'deviceId'),
          startedAt: any(named: 'startedAt'),
        ),
      ).thenAnswer((_) async => const Err(StorageFailure('disk full'))),
      act: (bloc) => bloc.add(const RecordingStarted('dev')),
      expect: () => const [RecordingIdle(failure: StorageFailure('disk full'))],
    );

    blocTest<PpgRecordingBloc, PpgRecordingState>(
      'write failure keeps recording and surfaces the failure',
      build: () =>
          PpgRecordingBloc(device: device, recording: failing, maxBatchSize: 2),
      setUp: () {
        when(
          () => failing.startSession(
            deviceId: any(named: 'deviceId'),
            startedAt: any(named: 'startedAt'),
          ),
        ).thenAnswer((_) async => Ok(session));
        when(
          () => failing.savePackets(any(), any()),
        ).thenAnswer((_) async => const Err(StorageFailure('io')));
      },
      act: (bloc) async {
        bloc.add(const RecordingStarted('dev'));
        await tick(10);
        packets(0, 1).forEach(live.add);
        await tick(10);
      },
      expect: () => [
        RecordingActive(session: session),
        RecordingActive(session: session, failure: const StorageFailure('io')),
      ],
    );
  });
}
