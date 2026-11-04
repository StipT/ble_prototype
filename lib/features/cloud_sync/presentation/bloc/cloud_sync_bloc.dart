import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/cloud_sync_repository.dart';
import '../../domain/connectivity_monitor.dart';
import '../../domain/entities/sync_counts.dart';

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------

/// Why an upload run was started.
enum CloudSyncTrigger {
  /// App start (after crash recovery).
  startup,

  /// The user pressed "Sync now" (also retries `failed` chunks).
  manual,

  /// The phone went from offline to online.
  connectivityRestored,

  /// A recording session ended, so its last partial chunk became eligible.
  sessionEnded,

  /// The backoff deadline of a pending chunk passed.
  retry,
}

/// Events of [CloudSyncBloc].
sealed class CloudSyncEvent extends Equatable {
  const CloudSyncEvent();

  @override
  List<Object?> get props => [];
}

/// Start the bloc: reset chunks interrupted by a crash, watch counts and
/// connectivity, then run a startup sync. Add once.
final class CloudSyncStarted extends CloudSyncEvent {
  /// Creates the event.
  const CloudSyncStarted();
}

/// Upload eligible chunks now, then prune old synced ones.
final class CloudSyncRequested extends CloudSyncEvent {
  /// [trigger] records why (defaults to the "Sync now" button).
  const CloudSyncRequested({this.trigger = CloudSyncTrigger.manual});

  /// Origin of the request.
  final CloudSyncTrigger trigger;

  @override
  List<Object?> get props => [trigger];
}

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

/// Phase of the upload engine.
enum CloudSyncStatus {
  /// No run yet.
  idle,

  /// Uploading.
  syncing,

  /// Last run finished (see [CloudSyncState.lastReport] for per-chunk
  /// results).
  done,

  /// Automatic trigger skipped: the phone is offline. Uploads resume when
  /// connectivity returns.
  offline,

  /// Last run could not start (sign-in or database error).
  failed,
}

/// State of [CloudSyncBloc].
final class CloudSyncState extends Equatable {
  /// Creates the state.
  const CloudSyncState({
    this.status = CloudSyncStatus.idle,
    this.counts = const SyncCounts(),
    this.online = true,
    this.trigger,
    this.lastReport,
    this.lastRunAt,
    this.failure,
  });

  /// Current phase.
  final CloudSyncStatus status;

  /// Chunks per upload state (live from the database).
  final SyncCounts counts;

  /// Last known connectivity.
  final bool online;

  /// Why the current/last run started.
  final CloudSyncTrigger? trigger;

  /// Result of the last completed run.
  final SyncReport? lastReport;

  /// End of the last completed run.
  final DateTime? lastRunAt;

  /// Why the last run could not start.
  final Failure? failure;

  /// Copy with changes; [failure] takes a closure so it can be cleared.
  CloudSyncState copyWith({
    CloudSyncStatus? status,
    SyncCounts? counts,
    bool? online,
    CloudSyncTrigger? trigger,
    SyncReport? lastReport,
    DateTime? lastRunAt,
    Failure? Function()? failure,
  }) => CloudSyncState(
    status: status ?? this.status,
    counts: counts ?? this.counts,
    online: online ?? this.online,
    trigger: trigger ?? this.trigger,
    lastReport: lastReport ?? this.lastReport,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [
    status,
    counts,
    online,
    trigger,
    lastReport,
    lastRunAt,
    failure,
  ];
}

// -----------------------------------------------------------------------------
// Bloc
// -----------------------------------------------------------------------------

/// Pushes local chunks to Firestore and prunes old uploaded ones.
///
/// **Triggers:** startup, connectivity regained (offline → online), session
/// end (the app forwards it from `PpgRecordingBloc` with a `BlocListener`),
/// the "Sync now" button, and the backoff deadline of a pending chunk.
///
/// **Concurrency:** uploads run in one `sequential()` handler, so two runs
/// never upload the same chunk concurrently. Automatic triggers are
/// coalesced (at most one queued), and skipped while offline so they don't
/// burn retry attempts; a manual request always runs and also retries
/// `failed` chunks. The counts subscription lives in a separate handler
/// (`emit.forEach`), so it never blocks the upload queue.
class CloudSyncBloc extends Bloc<CloudSyncEvent, CloudSyncState> {
  /// Creates the bloc; add [CloudSyncStarted] to start it.
  CloudSyncBloc({
    required CloudSyncRepository repository,
    required ConnectivityMonitor connectivity,
  }) : _repository = repository,
       _connectivity = connectivity,
       super(const CloudSyncState()) {
    on<CloudSyncStarted>(_onStarted);
    on<CloudSyncRequested>(_onRequested, transformer: sequential());
  }

  final CloudSyncRepository _repository;
  final ConnectivityMonitor _connectivity;

  Timer? _retryTimer;
  bool _autoQueued = false;
  bool _online = true;

  Future<void> _onStarted(
    CloudSyncStarted event,
    Emitter<CloudSyncState> emit,
  ) async {
    final recovered = await _repository.recoverInterrupted();
    if (recovered case Err(:final failure)) {
      emit(
        state.copyWith(status: CloudSyncStatus.failed, failure: () => failure),
      );
    }
    _requestAuto(CloudSyncTrigger.startup);
    bool? previous;
    // Two long-lived subscriptions owned by this handler; both end when the
    // bloc closes.
    await Future.wait([
      emit.forEach<SyncCounts>(
        _repository.watchCounts(),
        onData: (counts) => state.copyWith(counts: counts),
      ),
      emit.onEach<bool>(
        _connectivity.online,
        onData: (online) {
          _online = online;
          emit(state.copyWith(online: online));
          if (previous == false && online) {
            _requestAuto(CloudSyncTrigger.connectivityRestored);
          }
          previous = online;
        },
      ),
    ]);
  }

  void _requestAuto(CloudSyncTrigger trigger) {
    if (_autoQueued || isClosed) return;
    _autoQueued = true;
    add(CloudSyncRequested(trigger: trigger));
  }

  Future<void> _onRequested(
    CloudSyncRequested event,
    Emitter<CloudSyncState> emit,
  ) async {
    final manual = event.trigger == CloudSyncTrigger.manual;
    if (!manual) _autoQueued = false;
    if (!manual && !_online) {
      emit(
        state.copyWith(status: CloudSyncStatus.offline, trigger: event.trigger),
      );
      return;
    }
    _retryTimer?.cancel();
    emit(
      state.copyWith(
        status: CloudSyncStatus.syncing,
        trigger: event.trigger,
        failure: () => null,
      ),
    );

    final result = await _repository.uploadEligible(manual: manual);
    // Pruning is local-only and cheap; it also runs after a failed run.
    await _repository.pruneSynced();
    if (emit.isDone) return;

    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(
            status: CloudSyncStatus.done,
            lastReport: value,
            lastRunAt: clock.now(),
          ),
        );
        _scheduleRetry(value.nextRetryAt);
      case Err(:final failure):
        emit(
          state.copyWith(
            status: CloudSyncStatus.failed,
            lastRunAt: clock.now(),
            failure: () => failure,
          ),
        );
    }
  }

  void _scheduleRetry(DateTime? at) {
    if (at == null) return;
    final wait = at.difference(clock.now());
    _retryTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => _requestAuto(CloudSyncTrigger.retry),
    );
  }

  @override
  Future<void> close() async {
    _retryTimer?.cancel();
    return super.close();
  }
}
