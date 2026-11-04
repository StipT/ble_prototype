import 'dart:async';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/cloud_sync/domain/cloud_sync_repository.dart';
import 'package:ble_prototype/features/cloud_sync/domain/connectivity_monitor.dart';
import 'package:ble_prototype/features/cloud_sync/domain/entities/sync_counts.dart';
import 'package:ble_prototype/features/cloud_sync/presentation/bloc/cloud_sync_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements CloudSyncRepository {
  final List<String> calls = [];
  final counts = StreamController<SyncCounts>.broadcast();
  Result<SyncReport, Failure> result = const Ok(SyncReport());
  Completer<void>? gate;

  @override
  Future<Result<int, Failure>> recoverInterrupted() async {
    calls.add('recover');
    return const Ok(0);
  }

  @override
  Future<Result<SyncReport, Failure>> uploadEligible({
    bool manual = false,
  }) async {
    calls.add(manual ? 'upload(manual)' : 'upload');
    await gate?.future;
    return result;
  }

  @override
  Future<Result<int, Failure>> pruneSynced() async {
    calls.add('prune');
    return const Ok(0);
  }

  @override
  Stream<SyncCounts> watchCounts() => counts.stream;
}

class _FakeConnectivity implements ConnectivityMonitor {
  final controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get online => controller.stream;
}

void main() {
  late _FakeRepo repo;
  late _FakeConnectivity net;

  setUp(() {
    repo = _FakeRepo();
    net = _FakeConnectivity();
  });

  CloudSyncBloc build() => CloudSyncBloc(repository: repo, connectivity: net);

  blocTest<CloudSyncBloc, CloudSyncState>(
    'startup: recovers interrupted uploads, then syncs and prunes',
    build: build,
    act: (b) => b.add(const CloudSyncStarted()),
    wait: Duration.zero,
    expect: () => [
      const CloudSyncState(
        status: CloudSyncStatus.syncing,
        trigger: CloudSyncTrigger.startup,
      ),
      isA<CloudSyncState>()
          .having((s) => s.status, 'status', CloudSyncStatus.done)
          .having((s) => s.lastReport, 'report', const SyncReport()),
    ],
    verify: (_) => expect(repo.calls, ['recover', 'upload', 'prune']),
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'counts from the database are reflected in the state',
    build: build,
    act: (b) async {
      b.add(const CloudSyncStarted());
      await Future<void>.delayed(Duration.zero);
      repo.counts.add(const SyncCounts(pending: 3, synced: 2));
    },
    skip: 2,
    expect: () => [
      isA<CloudSyncState>().having(
        (s) => s.counts,
        'counts',
        const SyncCounts(pending: 3, synced: 2),
      ),
    ],
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'connectivity regained triggers a sync; going offline does not',
    build: build,
    act: (b) async {
      b.add(const CloudSyncStarted());
      await Future<void>.delayed(Duration.zero);
      net.controller.add(true);
      await Future<void>.delayed(Duration.zero);
      net.controller.add(false);
      await Future<void>.delayed(Duration.zero);
      repo.calls.clear();
      net.controller.add(true);
    },
    wait: const Duration(milliseconds: 10),
    verify: (b) {
      expect(repo.calls, ['upload', 'prune']);
      expect(b.state.trigger, CloudSyncTrigger.connectivityRestored);
      expect(b.state.online, isTrue);
    },
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'automatic triggers are skipped while offline; manual still runs',
    build: build,
    act: (b) async {
      b.add(const CloudSyncStarted());
      await Future<void>.delayed(Duration.zero);
      net.controller.add(false);
      await Future<void>.delayed(Duration.zero);
      repo.calls.clear();
      b.add(const CloudSyncRequested(trigger: CloudSyncTrigger.sessionEnded));
      await Future<void>.delayed(Duration.zero);
      expect(b.state.status, CloudSyncStatus.offline);
      b.add(const CloudSyncRequested());
    },
    wait: const Duration(milliseconds: 10),
    verify: (b) {
      expect(repo.calls, ['upload(manual)', 'prune']);
      expect(b.state.status, CloudSyncStatus.done);
    },
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'session end and Sync now run uploads; Sync now is manual',
    build: build,
    act: (b) async {
      b
        ..add(const CloudSyncRequested(trigger: CloudSyncTrigger.sessionEnded))
        ..add(const CloudSyncRequested());
    },
    wait: const Duration(milliseconds: 10),
    verify: (_) =>
        expect(repo.calls, ['upload', 'prune', 'upload(manual)', 'prune']),
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'runs are sequential and automatic triggers are coalesced',
    build: build,
    act: (b) async {
      repo.gate = Completer<void>();
      b.add(const CloudSyncStarted()); // startup run, blocked on the gate
      await Future<void>.delayed(Duration.zero);
      net.controller
        ..add(false)
        ..add(true) // queued
        ..add(false)
        ..add(true); // coalesced with the queued one
      await Future<void>.delayed(Duration.zero);
      b.add(const CloudSyncRequested(trigger: CloudSyncTrigger.sessionEnded));
      b.add(const CloudSyncRequested(trigger: CloudSyncTrigger.sessionEnded));
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, ['recover', 'upload'], reason: 'one at a time');
      repo.gate!.complete();
    },
    wait: const Duration(milliseconds: 10),
    verify: (_) => expect(repo.calls, [
      'recover',
      'upload',
      'prune',
      'upload',
      'prune',
      // The two explicit session-end events are separate requests.
      'upload',
      'prune',
      'upload',
      'prune',
    ]),
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'a run that cannot start reports the failure',
    setUp: () => repo.result = const Err(CloudFailure('no network')),
    build: build,
    act: (b) => b.add(const CloudSyncRequested()),
    wait: Duration.zero,
    expect: () => [
      isA<CloudSyncState>().having(
        (s) => s.status,
        'status',
        CloudSyncStatus.syncing,
      ),
      isA<CloudSyncState>()
          .having((s) => s.status, 'status', CloudSyncStatus.failed)
          .having(
            (s) => s.failure,
            'failure',
            const CloudFailure('no network'),
          ),
    ],
    verify: (_) => expect(repo.calls, ['upload(manual)', 'prune']),
  );

  blocTest<CloudSyncBloc, CloudSyncState>(
    'schedules an automatic retry at the backoff deadline',
    setUp: () => repo.result = Ok(
      SyncReport(
        retryScheduled: 1,
        nextRetryAt: DateTime.now().add(const Duration(milliseconds: 30)),
      ),
    ),
    build: build,
    act: (b) async {
      b.add(const CloudSyncRequested());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      repo.result = const Ok(SyncReport(uploaded: 1));
    },
    wait: const Duration(milliseconds: 100),
    verify: (b) {
      expect(repo.calls, ['upload(manual)', 'prune', 'upload', 'prune']);
      expect(b.state.trigger, CloudSyncTrigger.retry);
      expect(b.state.lastReport, const SyncReport(uploaded: 1));
    },
  );
}
