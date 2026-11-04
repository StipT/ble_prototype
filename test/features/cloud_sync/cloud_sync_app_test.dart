import 'package:ble_prototype/app/app.dart';
import 'package:ble_prototype/core/config/app_config.dart';
import 'package:ble_prototype/core/di/injection.dart';
import 'package:ble_prototype/features/cloud_sync/data/connectivity_plus_monitor.dart';
import 'package:ble_prototype/features/cloud_sync/presentation/bloc/cloud_sync_bloc.dart';
import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/ppg_recording/domain/recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/bloc/ppg_recording_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_cloud_remote.dart';
import '../../helpers/packets.dart';
import '../../helpers/test_database.dart';

void main() {
  tearDown(() => sl.reset());

  testWidgets('ending a session uploads its chunks; Sync now shows counts', (
    tester,
  ) async {
    final remote = FakeCloudRemote();
    await configureDependencies(
      const AppConfig(enableFirebase: false),
      database: testDatabase(),
      cloudRemote: remote,
      connectivity: const StaticConnectivityMonitor(),
    );
    await tester.pumpWidget(const PpgApp());
    await tester.pump();

    final recorder = BlocProvider.of<PpgRecordingBloc>(
      tester.element(find.byType(HomeShell)),
    );
    // Alternates fake time with a real event-loop turn: some futures (e.g.
    // a cancelled broadcast subscription's) complete in the root zone,
    // which pump() alone never drives.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    }

    recorder.add(const RecordingStarted(FakePpgDevice.defaultDeviceId));
    await settle();
    final sessionId = (recorder.state as RecordingActive).session.id;
    // Packets as if recorded: one full chunk plus a partial one.
    sl<RecordingRepository>().savePackets(sessionId, packets(0, 149)).ignore();
    await settle();
    expect(remote.chunks, isEmpty, reason: 'no trigger while recording');

    recorder.add(const RecordingStopped());
    await settle();
    expect(recorder.state, isA<RecordingIdle>());

    expect(await _chunkStates(tester), {
      0: ChunkSyncState.synced,
      1: ChunkSyncState.synced,
    });
    expect(remote.chunks.keys.toSet(), {
      'test-uid/${sessionId}_0',
      'test-uid/${sessionId}_1',
    });
    expect(remote.chunks['test-uid/${sessionId}_1']!.packetCount, 50);
    expect(remote.sessions['test-uid/$sessionId']!.endedAt, isNotNull);

    await tester.tap(find.text('Sessions'));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('cloud-sync-counts'))).data,
      // Test packets are stamped 2026-01-01, older than the 7-day retention,
      // so the run after the upload pruned them right away.
      'Chunks: 0 pending · 0 uploading · 2 synced · 0 failed · 2 pruned',
    );

    await tester.tap(find.byKey(const Key('cloud-sync-button')));
    await settle();
    final cloud = BlocProvider.of<CloudSyncBloc>(
      tester.element(find.byType(HomeShell)),
    );
    expect(cloud.state.trigger, CloudSyncTrigger.manual);
    expect(cloud.state.status, CloudSyncStatus.done);

    sl<FakePpgDevice>().dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

/// Chunk index → sync state of every local chunk.
Future<Map<int, ChunkSyncState>> _chunkStates(WidgetTester tester) async {
  final db = sl<AppDatabase>();
  Map<int, ChunkSyncState>? result;
  db
      .select(db.chunks)
      .get()
      .then(
        (rows) => result = {for (final r in rows) r.chunkIndex: r.syncState},
      )
      .ignore();
  await tester.pump();
  return result!;
}
