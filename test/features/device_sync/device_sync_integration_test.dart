import 'dart:async';
import 'dart:math' as math;

import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/stream/stream_extensions.dart';
import 'package:ble_prototype/features/device_connection/data/device_repository_impl.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/device_connection/data/fake/ppg_signal_generator.dart';
import 'package:ble_prototype/features/device_connection/domain/reconnect_policy.dart';
import 'package:ble_prototype/features/device_connection/presentation/bloc/device_connection_bloc.dart';
import 'package:ble_prototype/features/device_sync/presentation/bloc/device_sync_bloc.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/bloc/ppg_recording_bloc.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

/// End-to-end: FakePpgDevice → DeviceRepositoryImpl → connection, recording
/// and history-sync blocs → Drift, all in fake time.
void main() {
  test('dropped packets, an outage and a mid-sync disconnect end with a '
      'gap-free, duplicate-free session', () {
    fakeAsync((async) {
      final device = FakePpgDevice(
        random: math.Random(1),
        generator: PpgSignalGenerator(random: math.Random(2)),
      );
      final repo = DeviceRepositoryImpl(adapter: device);
      final db = testDatabase();
      final recording = DriftRecordingRepository(db);
      final connection = DeviceConnectionBloc(
        device: repo,
        policy: const ReconnectPolicy(maxDelay: Duration(seconds: 4)),
      );
      final recorder = PpgRecordingBloc(device: repo, recording: recording);
      final sync = DeviceSyncBloc(
        device: repo,
        recording: recording,
        linkReady: connection.stream
            .startWith(() => connection.state)
            .map((s) => s.isConnected)
            .distinct(),
        maxRangeLength: 100,
      );

      final syncStates = <DeviceSyncState>[];
      var interruptMidSync = false;
      var interrupted = false;
      sync.stream.listen((s) {
        syncStates.add(s);
        if (interruptMidSync &&
            !interrupted &&
            s.status == DeviceSyncStatus.syncing &&
            s.packetsReceived > 0) {
          interrupted = true;
          device.simulateDisconnect();
        }
      });

      async.elapse(const Duration(seconds: 2)); // backlog before connecting
      connection.add(
        const DeviceConnectRequested(FakePpgDevice.defaultDeviceId),
      );
      async.elapse(const Duration(seconds: 1));
      expect(connection.state.isConnected, isTrue);

      recorder.add(const RecordingStarted(FakePpgDevice.defaultDeviceId));
      async.elapse(const Duration(seconds: 3));

      // 1) Notifications lost in the air → live gap → gap sync.
      device.dropNextPackets(5);
      async.elapse(const Duration(seconds: 4));
      expect(
        syncStates.where((s) => s.trigger == DeviceSyncTrigger.liveGap).last,
        isA<DeviceSyncState>()
            .having((s) => s.status, 'status', DeviceSyncStatus.upToDate)
            .having((s) => s.packetsSaved, 'saved', greaterThanOrEqualTo(5)),
      );

      // 2) User walks away for 20 s; the device keeps storing. On the
      //    reconnect the sync starts and the link drops again mid-download.
      interruptMidSync = true;
      device.simulateOutage(const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 60));
      expect(interrupted, isTrue);
      expect(
        syncStates.where((s) => s.status == DeviceSyncStatus.failed),
        isNotEmpty,
      );
      expect(
        syncStates
            .firstWhere((s) => s.status == DeviceSyncStatus.failed)
            .failure,
        isA<ConnectionLost>(),
      );
      expect(connection.state.isConnected, isTrue);
      expect(sync.state.status, DeviceSyncStatus.upToDate);
      expect(sync.state.trigger, DeviceSyncTrigger.connected);
      // The resumed run asked only for what the interrupted one missed.
      final failedRun = syncStates.firstWhere(
        (s) => s.status == DeviceSyncStatus.failed,
      );
      expect(sync.state.packetsSaved, greaterThan(0));
      expect(sync.state.packetsRequested, lessThan(failedRun.packetsRequested));

      async.elapse(const Duration(seconds: 2));
      recorder.add(const RecordingStopped());
      async.elapse(const Duration(seconds: 2));

      List<PacketRow>? rows;
      List<ChunkRow>? chunks;
      db.select(db.packets).get().then((r) => rows = r);
      db.select(db.chunks).get().then((c) => chunks = c);
      async.flushMicrotasks();

      final seqs = rows!.map((r) => r.sequence).toList()..sort();
      final first = seqs.first;
      final last = seqs.last;
      expect(last - first, greaterThan(500), reason: '~70 s recorded');
      // Gap-free and duplicate-free: exactly one row per sequence number.
      expect(seqs, List.generate(last - first + 1, (i) => first + i));
      // Chunk aggregates count every packet exactly once as well.
      expect(chunks!.fold<int>(0, (n, c) => n + c.packetCount), seqs.length);
      // The outage (~200+ packets) and the dropped ones came from history.
      expect(
        rows!.where((r) => r.fromHistory).length,
        greaterThanOrEqualTo(205),
      );

      unawaited(sync.close());
      unawaited(recorder.close());
      unawaited(connection.close());
      device.dispose();
      unawaited(db.close());
      async.flushTimers();
    });
  });
}
