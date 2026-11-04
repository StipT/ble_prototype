import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../device_connection/domain/device_repository.dart';
import '../../../device_connection/domain/entities/ble_types.dart';
import '../../../device_connection/domain/entities/ppg_packet.dart';
import '../../../ppg_recording/domain/entities/sequence_range.dart';
import '../../../ppg_recording/domain/recording_repository.dart';

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------

/// Why a history sync was started.
enum DeviceSyncTrigger {
  /// The user pressed "Sync history".
  manual,

  /// The BLE link became ready (first connect or automatic reconnect). The
  /// device kept measuring while the phone was away; fetch what it stored.
  connected,

  /// A live notification arrived with a sequence number that skipped some:
  /// notifications were lost in the air (BLE notifications are
  /// unacknowledged, so a missed one is simply gone — only the device's
  /// backlog still has it).
  liveGap,
}

/// Events of [DeviceSyncBloc].
sealed class DeviceSyncEvent extends Equatable {
  const DeviceSyncEvent();

  @override
  List<Object?> get props => [];
}

/// Download every missing range of the active session from the device
/// backlog.
final class DeviceSyncRequested extends DeviceSyncEvent {
  /// [trigger] records why (shown in the UI, useful in logs).
  const DeviceSyncRequested({this.trigger = DeviceSyncTrigger.manual});

  /// Origin of the request.
  final DeviceSyncTrigger trigger;

  @override
  List<Object?> get props => [trigger];
}

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

/// Phase of the history sync.
enum DeviceSyncStatus {
  /// No sync has run yet.
  idle,

  /// Downloading missing ranges.
  syncing,

  /// Every replayable range of the active session is stored.
  upToDate,

  /// Nothing to sync into: no recording session is open (the device only
  /// keeps a short backlog, and recording = persisting).
  noSession,

  /// The last sync stopped early (link lost, device silent, storage error).
  /// The next trigger resumes from what is already in the database.
  failed,
}

/// State of [DeviceSyncBloc]: phase plus progress counters of the current
/// (or last) run.
final class DeviceSyncState extends Equatable {
  /// Creates the state.
  const DeviceSyncState({
    this.status = DeviceSyncStatus.idle,
    this.trigger,
    this.sessionId,
    this.rangesTotal = 0,
    this.rangesDone = 0,
    this.packetsRequested = 0,
    this.packetsReceived = 0,
    this.packetsSaved = 0,
    this.lastCompletedAt,
    this.failure,
  });

  /// Current phase.
  final DeviceSyncStatus status;

  /// Why the current/last run started.
  final DeviceSyncTrigger? trigger;

  /// Session the history is written into.
  final String? sessionId;

  /// History requests planned for this run (after splitting long ranges).
  final int rangesTotal;

  /// History requests fully answered so far.
  final int rangesDone;

  /// Packets asked for in this run.
  final int packetsRequested;

  /// History packets received (and handed to the database) in this run.
  final int packetsReceived;

  /// Of those, packets that were new to the database (the rest were already
  /// stored, e.g. as a live copy, and were de-duplicated by the primary
  /// key).
  final int packetsSaved;

  /// End of the last successful run.
  final DateTime? lastCompletedAt;

  /// Why the last run failed.
  final Failure? failure;

  /// 0..1 progress of a run, `null` when nothing is requested.
  double? get progress => packetsRequested == 0
      ? null
      : (packetsReceived / packetsRequested).clamp(0, 1).toDouble();

  /// Copy with changes; [failure] takes a closure so it can be cleared.
  DeviceSyncState copyWith({
    DeviceSyncStatus? status,
    DeviceSyncTrigger? trigger,
    int? rangesDone,
    int? packetsReceived,
    int? packetsSaved,
    DateTime? lastCompletedAt,
    Failure? Function()? failure,
  }) => DeviceSyncState(
    status: status ?? this.status,
    trigger: trigger ?? this.trigger,
    sessionId: sessionId,
    rangesTotal: rangesTotal,
    rangesDone: rangesDone ?? this.rangesDone,
    packetsRequested: packetsRequested,
    packetsReceived: packetsReceived ?? this.packetsReceived,
    packetsSaved: packetsSaved ?? this.packetsSaved,
    lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [
    status,
    trigger,
    sessionId,
    rangesTotal,
    rangesDone,
    packetsRequested,
    packetsReceived,
    packetsSaved,
    lastCompletedAt,
    failure,
  ];
}

// -----------------------------------------------------------------------------
// Bloc
// -----------------------------------------------------------------------------

/// Fills the holes in the active recording from the wearable's **stored
/// backlog**, requesting missing ranges by sequence number.
///
/// How BLE history download works here:
/// * The wearable stamps every packet with a device-wide sequence number and
///   keeps the last few minutes in a ring buffer (`oldestSequence ..
///   latestSequence`, read from the status characteristic) whether or not a
///   phone is connected.
/// * Live data travels as GATT *notifications*, which are unacknowledged: a
///   notification lost to interference, or produced while the link was
///   down, never arrives. Instead of trusting the stream, the app treats the
///   **database as the source of truth** and asks
///   [RecordingRepository.missingRanges] which sequence numbers are absent.
/// * Each missing range is requested with a *write* to the control
///   characteristic (`RequestHistoryCommand(from, to)`); the device answers
///   with notifications of kind `history`, then an end-of-replay frame
///   ([DeviceRepository.downloadHistory]).
/// * Packets are saved in batches of [batchSize] as they arrive (one
///   transaction each). The `(sessionId, sequence)` primary key
///   de-duplicates them against live copies and against an earlier,
///   interrupted run.
///
/// **Resume:** if the link drops mid-download, the packets received so far
/// are already stored, the run ends in [DeviceSyncStatus.failed], and the
/// next run (triggered by the reconnect) recomputes the missing ranges from
/// the database — so it continues exactly where the last one stopped, with
/// no duplicates and no gaps.
///
/// **Triggers:** the link becoming ready (`linkReady` emits `true`), a
/// sequence gap in the live stream (after [gapSettleDelay]), or a manual
/// [DeviceSyncRequested].
///
/// **Concurrency:** one handler with `sequential()`. Two runs never download
/// at the same time (the device replays one range at a time, and two
/// overlapping replays would interleave on the same characteristic), and a
/// request arriving during a run starts after it — recomputing the ranges,
/// so it never re-downloads what the previous run stored. Automatic
/// triggers are coalesced: at most one automatic run is queued.
class DeviceSyncBloc extends Bloc<DeviceSyncEvent, DeviceSyncState> {
  /// Creates the bloc.
  ///
  /// [device] talks to the wearable; [recording] owns the database.
  /// [linkReady] must emit `true` once a (re)connection is fully set up —
  /// connected, MTU negotiated, streaming started — and `false` when the
  /// link is lost. Requesting history any earlier could hit the default
  /// 23-byte ATT MTU (20-byte payload), and the 29-byte replayed packets
  /// would be truncated. [batchSize] is the number of packets per database
  /// transaction. [maxRangeLength] caps a single history request (300
  /// packets = 30 s of signal), bounding what an interruption costs.
  /// [idleTimeout] is how long the device may stay silent during a replay
  /// before the run fails. [gapSettleDelay] gives the recorder time to
  /// persist the live packets around a detected gap before the missing
  /// ranges are computed.
  DeviceSyncBloc({
    required DeviceRepository device,
    required RecordingRepository recording,
    required Stream<bool> linkReady,
    this.batchSize = 50,
    this.maxRangeLength = 300,
    this.idleTimeout = const Duration(seconds: 5),
    this.gapSettleDelay = const Duration(seconds: 1),
  }) : assert(batchSize > 0 && maxRangeLength > 0, 'sizes must be positive'),
       _device = device,
       _recording = recording,
       super(const DeviceSyncState()) {
    on<DeviceSyncEvent>(_onEvent, transformer: sequential());
    _readySubscription = linkReady.listen(_onLinkReady, onError: addError);
    _liveSubscription = _device.livePackets.listen(
      _onLivePacket,
      onError: addError,
    );
  }

  final DeviceRepository _device;
  final RecordingRepository _recording;

  /// Packets per database transaction.
  final int batchSize;

  /// Longest single history request, in packets.
  final int maxRangeLength;

  /// Maximum silence of the device during one replay.
  final Duration idleTimeout;

  /// Wait between detecting a live gap and starting the sync.
  final Duration gapSettleDelay;

  late final StreamSubscription<bool> _readySubscription;
  late final StreamSubscription<PpgPacket> _liveSubscription;
  int? _lastLiveSequence;
  Timer? _gapTimer;
  bool _autoQueued = false;

  void _onLinkReady(bool ready) {
    // A new link starts a new live stream; the jump from the last packet of
    // the previous link is covered by the "connected" sync, not a gap sync.
    _lastLiveSequence = null;
    if (ready) _requestAuto(DeviceSyncTrigger.connected);
  }

  void _onLivePacket(PpgPacket packet) {
    final last = _lastLiveSequence;
    if (last == null || packet.sequence > last) {
      _lastLiveSequence = packet.sequence;
    }
    if (last != null && packet.sequence > last + 1) {
      _gapTimer ??= Timer(gapSettleDelay, () {
        _gapTimer = null;
        _requestAuto(DeviceSyncTrigger.liveGap);
      });
    }
  }

  void _requestAuto(DeviceSyncTrigger trigger) {
    if (_autoQueued || isClosed) return;
    _autoQueued = true;
    add(DeviceSyncRequested(trigger: trigger));
  }

  Future<void> _onEvent(DeviceSyncEvent event, Emitter<DeviceSyncState> emit) =>
      switch (event) {
        DeviceSyncRequested(:final trigger) => _sync(trigger, emit),
      };

  Future<void> _sync(
    DeviceSyncTrigger trigger,
    Emitter<DeviceSyncState> emit,
  ) async {
    _autoQueued = false;

    void fail(Failure failure) => emit(
      state.copyWith(
        status: DeviceSyncStatus.failed,
        trigger: trigger,
        failure: () => failure,
      ),
    );

    if (_device.currentLinkState != DeviceLinkState.connected) {
      return fail(const ConnectionLost('Not connected to the device'));
    }

    final planned = await _plan();
    if (emit.isDone) return;
    if (planned case Err(:final failure)) return fail(failure);
    final plan = planned.valueOrNull;
    if (plan == null) {
      emit(
        DeviceSyncState(
          status: DeviceSyncStatus.noSession,
          trigger: trigger,
          lastCompletedAt: state.lastCompletedAt,
        ),
      );
      return;
    }

    emit(
      DeviceSyncState(
        status: DeviceSyncStatus.syncing,
        trigger: trigger,
        sessionId: plan.sessionId,
        rangesTotal: plan.requests.length,
        packetsRequested: plan.requests.fold(0, (n, r) => n + r.length),
        lastCompletedAt: state.lastCompletedAt,
      ),
    );

    for (final range in plan.requests) {
      final failure = await _download(plan.sessionId, range, emit);
      if (emit.isDone) return;
      if (failure != null) return fail(failure);
      emit(state.copyWith(rangesDone: state.rangesDone + 1));
    }
    emit(
      state.copyWith(
        status: DeviceSyncStatus.upToDate,
        lastCompletedAt: clock.now(),
        failure: () => null,
      ),
    );
  }

  /// Active session + device backlog bounds → list of history requests.
  /// `Ok(null)` means there is no open session to fill.
  Future<Result<_Plan?, Failure>> _plan() async {
    final session = await _recording.activeSession();
    if (session case Err(:final failure)) return Err(failure);
    final active = session.valueOrNull;
    if (active == null) return const Ok(null);

    // The backlog bounds live on the status characteristic; a GATT *read*
    // returns them on demand instead of waiting for the next notification.
    final status = await _device.readStatus();
    if (status case Err(:final failure)) return Err(failure);
    final device = status.valueOrNull!;
    if (!device.hasData) return Ok(_Plan(active.id, const []));

    final missing = await _recording.missingRanges(
      active.id,
      notBefore: device.oldestSequence,
      upTo: device.latestSequence,
    );
    if (missing case Err(:final failure)) return Err(failure);
    return Ok(
      _Plan(active.id, [
        for (final r in missing.valueOrNull!) ...r.split(maxRangeLength),
      ]),
    );
  }

  /// Downloads one [range] into [sessionId], saving every [batchSize]
  /// packets. Returns the failure that ended the download early, if any;
  /// packets received before it are always saved first.
  Future<Failure?> _download(
    String sessionId,
    SequenceRange range,
    Emitter<DeviceSyncState> emit,
  ) async {
    final buffer = <PpgPacket>[];
    Failure? failure;

    Future<void> flush() async {
      if (buffer.isEmpty) return;
      final batch = List<PpgPacket>.of(buffer);
      buffer.clear();
      final saved = await _recording.savePackets(sessionId, batch);
      if (emit.isDone) return;
      switch (saved) {
        case Ok(:final value):
          emit(
            state.copyWith(
              packetsReceived: state.packetsReceived + batch.length,
              packetsSaved: state.packetsSaved + value,
            ),
          );
        case Err(failure: final f):
          failure ??= f;
      }
    }

    try {
      // `await flush()` inside `await for` pauses the subscription; the
      // history stream buffers meanwhile, so nothing is lost while writing.
      await for (final packet in _device.downloadHistory(
        range.from,
        range.to,
        idleTimeout: idleTimeout,
      )) {
        buffer.add(packet);
        if (buffer.length >= batchSize) {
          await flush();
          if (failure != null || emit.isDone) break;
        }
      }
    } on Failure catch (f) {
      failure = f;
    }
    await flush();
    return failure;
  }

  @override
  Future<void> close() async {
    _gapTimer?.cancel();
    await _readySubscription.cancel();
    await _liveSubscription.cancel();
    return super.close();
  }
}

/// What one run will request: the target session and its history requests.
class _Plan {
  const _Plan(this.sessionId, this.requests);

  final String sessionId;
  final List<SequenceRange> requests;
}
