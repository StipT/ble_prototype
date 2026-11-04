import 'dart:async';

import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/device_connection/domain/device_repository.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ble_types.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/device_status.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:ble_prototype/features/device_sync/presentation/bloc/device_sync_bloc.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/packets.dart';
import '../../../helpers/test_database.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

DeviceStatus _status({required int oldest, required int latest}) =>
    DeviceStatus(
      batteryPercent: 90,
      isStreaming: true,
      isCharging: false,
      hasData: true,
      oldestSequence: oldest,
      latestSequence: latest,
    );

void main() {
  late _MockDeviceRepository device;
  late StreamController<PpgPacket> live;
  late StreamController<bool> ready;
  late AppDatabase db;
  late DriftRecordingRepository recording;
  late DeviceLinkState link;
  late DeviceStatus status;
  late List<(int, int)> requests;

  /// Per-call override of the device's history replay. Returning `null`
  /// replays the requested range completely.
  late Stream<PpgPacket>? Function(int from, int to) replay;

  setUpAll(() => registerFallbackValue(Duration.zero));

  setUp(() {
    device = _MockDeviceRepository();
    live = StreamController<PpgPacket>.broadcast();
    ready = StreamController<bool>.broadcast();
    db = testDatabase();
    recording = DriftRecordingRepository(db);
    link = DeviceLinkState.connected;
    status = _status(oldest: 0, latest: 0);
    requests = [];
    replay = (_, _) => null;

    when(() => device.livePackets).thenAnswer((_) => live.stream);
    when(() => device.currentLinkState).thenAnswer((_) => link);
    when(() => device.readStatus()).thenAnswer((_) async => Ok(status));
    when(
      () => device.downloadHistory(
        any(),
        any(),
        idleTimeout: any(named: 'idleTimeout'),
      ),
    ).thenAnswer((inv) {
      final from = inv.positionalArguments[0] as int;
      final to = inv.positionalArguments[1] as int;
      requests.add((from, to));
      return replay(from, to) ??
          Stream.fromIterable(packets(from, to, kind: PpgPacketKind.history));
    });
  });

  tearDown(() async {
    await live.close();
    await ready.close();
    await db.close();
  });

  Future<String> openSession(List<PpgPacket> stored) async {
    final id = (await recording.startSession(
      deviceId: 'dev',
      startedAt: DateTime.utc(2026),
    )).valueOrNull!.id;
    await recording.savePackets(id, stored);
    return id;
  }

  Future<List<PacketRow>> rows() => (db.select(
    db.packets,
  )..orderBy([(p) => OrderingTerm.asc(p.sequence)])).get();

  DeviceSyncBloc build({int batchSize = 4, int maxRangeLength = 10}) =>
      DeviceSyncBloc(
        device: device,
        recording: recording,
        linkReady: ready.stream,
        batchSize: batchSize,
        maxRangeLength: maxRangeLength,
        gapSettleDelay: const Duration(milliseconds: 20),
      );

  Future<void> settle([int ms = 50]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  blocTest<DeviceSyncBloc, DeviceSyncState>(
    'without an open session there is nothing to sync into',
    build: build,
    act: (b) => b.add(const DeviceSyncRequested()),
    expect: () => const [
      DeviceSyncState(
        status: DeviceSyncStatus.noSession,
        trigger: DeviceSyncTrigger.manual,
      ),
    ],
    verify: (_) => verifyNever(
      () => device.downloadHistory(
        any(),
        any(),
        idleTimeout: any(named: 'idleTimeout'),
      ),
    ),
  );

  blocTest<DeviceSyncBloc, DeviceSyncState>(
    'fails with ConnectionLost while the link is down',
    setUp: () => link = DeviceLinkState.disconnected,
    build: build,
    act: (b) => b.add(const DeviceSyncRequested()),
    expect: () => [
      isA<DeviceSyncState>()
          .having((s) => s.status, 'status', DeviceSyncStatus.failed)
          .having((s) => s.failure, 'failure', isA<ConnectionLost>()),
    ],
  );

  group('with an open session', () {
    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'requests gaps + tail (clipped to the backlog, split), saves in '
      'batches and ends gap-free',
      setUp: () async {
        await openSession([...packets(0, 9), ...packets(20, 29)]);
        // Backlog 5..44: gap 10..19, tail 30..44 (split at 10).
        status = _status(oldest: 5, latest: 44);
      },
      build: build,
      act: (b) => b.add(const DeviceSyncRequested()),
      expect: () => [
        isA<DeviceSyncState>()
            .having((s) => s.status, 'status', DeviceSyncStatus.syncing)
            .having((s) => s.rangesTotal, 'ranges', 3)
            .having((s) => s.packetsRequested, 'requested', 25)
            .having((s) => s.progress, 'progress', 0),
        // 10..19 → batches of 4,4,2 then "range done"; same for 30..39;
        // 40..44 → 4,1 then range done; finally up to date.
        ...List.filled(
          11,
          isA<DeviceSyncState>().having(
            (s) => s.status,
            'status',
            DeviceSyncStatus.syncing,
          ),
        ),
        isA<DeviceSyncState>()
            .having((s) => s.status, 'status', DeviceSyncStatus.upToDate)
            .having((s) => s.rangesDone, 'rangesDone', 3)
            .having((s) => s.packetsReceived, 'received', 25)
            .having((s) => s.packetsSaved, 'saved', 25)
            .having((s) => s.progress, 'progress', 1)
            .having((s) => s.lastCompletedAt, 'completedAt', isNotNull),
      ],
      verify: (_) async {
        expect(requests, [(10, 19), (30, 39), (40, 44)]);
        final stored = await rows();
        expect(stored.map((r) => r.sequence), List.generate(45, (i) => i));
        expect(stored.where((r) => r.fromHistory).map((r) => r.sequence), [
          ...List.generate(10, (i) => 10 + i),
          ...List.generate(15, (i) => 30 + i),
        ]);
      },
    );

    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'packets already stored live are de-duplicated (counted as received, '
      'not saved)',
      setUp: () async {
        await openSession([...packets(0, 4), ...packets(8, 9)]);
        status = _status(oldest: 0, latest: 9);
        // The device replays more than asked (e.g. a sloppy firmware).
        replay = (from, to) => Stream.fromIterable(
          packets(from - 1, to + 1, kind: PpgPacketKind.history),
        );
      },
      build: build,
      act: (b) => b.add(const DeviceSyncRequested()),
      skip: 1,
      verify: (b) async {
        expect(b.state.status, DeviceSyncStatus.upToDate);
        expect(b.state.packetsReceived, 5);
        expect(b.state.packetsSaved, 3);
        expect(
          (await rows()).map((r) => r.sequence),
          List.generate(10, (i) => i),
        );
      },
    );

    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'link lost mid-download: keeps what arrived, then resumes exactly '
      'where it stopped — no duplicates, no gaps',
      setUp: () async {
        await openSession(packets(0, 9));
        status = _status(oldest: 0, latest: 39);
        var first = true;
        replay = (from, to) {
          if (!first) return null;
          first = false;
          // 7 packets arrive, then the radio link drops.
          final c = StreamController<PpgPacket>();
          packets(from, from + 6, kind: PpgPacketKind.history).forEach(c.add);
          c
            ..addError(const ConnectionLost('Link dropped'))
            ..close();
          return c.stream;
        };
      },
      build: () => build(maxRangeLength: 100),
      act: (b) async {
        b.add(const DeviceSyncRequested());
        await settle();
        // Reconnected: the connection bloc reports the link ready again.
        ready.add(true);
        await settle();
      },
      expect: () => [
        isA<DeviceSyncState>().having(
          (s) => s.packetsRequested,
          'requested',
          30,
        ),
        isA<DeviceSyncState>().having((s) => s.packetsReceived, 'rcv', 4),
        isA<DeviceSyncState>().having((s) => s.packetsReceived, 'rcv', 7),
        isA<DeviceSyncState>()
            .having((s) => s.status, 'status', DeviceSyncStatus.failed)
            .having((s) => s.failure, 'failure', isA<ConnectionLost>()),
        // Resume: only the 23 packets still missing are requested.
        isA<DeviceSyncState>()
            .having((s) => s.status, 'status', DeviceSyncStatus.syncing)
            .having((s) => s.trigger, 'trigger', DeviceSyncTrigger.connected)
            .having((s) => s.packetsRequested, 'requested', 23)
            .having((s) => s.failure, 'failure', isNull),
        ...List.filled(
          7,
          isA<DeviceSyncState>().having(
            (s) => s.status,
            'status',
            DeviceSyncStatus.syncing,
          ),
        ),
        isA<DeviceSyncState>()
            .having((s) => s.status, 'status', DeviceSyncStatus.upToDate)
            .having((s) => s.packetsSaved, 'saved', 23),
      ],
      verify: (_) async {
        expect(requests, [(10, 39), (17, 39)]);
        expect(
          (await rows()).map((r) => r.sequence),
          List.generate(40, (i) => i),
        );
        final chunk = await db.select(db.chunks).getSingle();
        expect(chunk.packetCount, 40);
      },
    );

    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'sequential(): a request during a run waits, then finds nothing left',
      setUp: () async {
        await openSession(packets(0, 4));
        status = _status(oldest: 0, latest: 24);
      },
      build: build,
      act: (b) async {
        b
          ..add(const DeviceSyncRequested())
          ..add(const DeviceSyncRequested());
        await settle();
      },
      skip: 1,
      verify: (b) async {
        // One download for 5..14 and 15..24; the second run requested none.
        expect(requests, [(5, 14), (15, 24)]);
        expect(b.state.status, DeviceSyncStatus.upToDate);
        expect(b.state.packetsRequested, 0);
        expect((await rows()).length, 25);
      },
    );

    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'a storage failure ends the run as failed',
      setUp: () async {
        await openSession(packets(0, 4));
        status = _status(oldest: 0, latest: 9);
      },
      build: () => DeviceSyncBloc(
        device: device,
        recording: _FailingWrites(db),
        linkReady: ready.stream,
      ),
      act: (b) => b.add(const DeviceSyncRequested()),
      skip: 1,
      verify: (b) {
        expect(b.state.status, DeviceSyncStatus.failed);
        expect(b.state.failure, const StorageFailure('disk full'));
        expect(b.state.packetsReceived, 0);
      },
    );
  });

  group('automatic triggers', () {
    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'link becoming ready starts a sync; link loss does not',
      setUp: () async {
        await openSession(packets(0, 4));
        status = _status(oldest: 0, latest: 7);
      },
      build: build,
      act: (b) async {
        ready.add(false);
        await settle();
        ready.add(true);
        await settle();
      },
      skip: 1,
      verify: (b) {
        expect(requests, [(5, 7)]);
        expect(b.state.trigger, DeviceSyncTrigger.connected);
        expect(b.state.status, DeviceSyncStatus.upToDate);
      },
    );

    blocTest<DeviceSyncBloc, DeviceSyncState>(
      'a sequence gap in the live stream starts one sync after settling',
      setUp: () async {
        await openSession(packets(0, 4));
        status = _status(oldest: 0, latest: 12);
      },
      build: build,
      act: (b) async {
        // 5 and 6 were lost in the air; 9 and 10 too.
        [
          packet(4),
          packet(7),
          packet(8),
          packet(11),
          packet(12),
        ].forEach(live.add);
        await settle(5);
        expect(requests, isEmpty, reason: 'waits for gapSettleDelay');
        await settle(100);
      },
      skip: 1,
      verify: (b) {
        expect(requests, [(5, 12)]);
        expect(b.state.trigger, DeviceSyncTrigger.liveGap);
      },
    );
  });
}

/// Real reads, failing writes.
class _FailingWrites extends DriftRecordingRepository {
  _FailingWrites(super.db);

  @override
  Future<Result<int, Failure>> savePackets(
    String sessionId,
    List<PpgPacket> packets,
  ) async => const Err(StorageFailure('disk full'));
}
