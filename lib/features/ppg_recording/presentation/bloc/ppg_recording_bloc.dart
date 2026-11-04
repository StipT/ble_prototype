import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../../core/util/batcher.dart';
import '../../../device_connection/domain/device_repository.dart';
import '../../../device_connection/domain/entities/ppg_packet.dart';
import '../../domain/entities/session.dart';
import '../../domain/recording_repository.dart';

/// Events of [PpgRecordingBloc].
sealed class PpgRecordingEvent extends Equatable {
  const PpgRecordingEvent();

  @override
  List<Object?> get props => [];
}

/// User pressed "Record".
final class RecordingStarted extends PpgRecordingEvent {
  /// [deviceId] is stored on the session.
  const RecordingStarted(this.deviceId);

  /// Producing wearable.
  final String deviceId;

  @override
  List<Object?> get props => [deviceId];
}

/// User pressed "Stop".
final class RecordingStopped extends PpgRecordingEvent {
  /// Creates the event.
  const RecordingStopped();
}

/// Internal: a batch of live packets is ready to be persisted.
final class _BatchReady extends PpgRecordingEvent {
  const _BatchReady(this.batch);

  final List<PpgPacket> batch;

  @override
  List<Object?> get props => [batch];
}

/// States of [PpgRecordingBloc].
sealed class PpgRecordingState extends Equatable {
  const PpgRecordingState();
}

/// Not recording.
final class RecordingIdle extends PpgRecordingState {
  /// [lastSession] is the session that just ended; [failure] the last error.
  const RecordingIdle({this.lastSession, this.failure});

  /// Most recently finished session.
  final Session? lastSession;

  /// Why the last action failed, if it did.
  final Failure? failure;

  @override
  List<Object?> get props => [lastSession, failure];
}

/// Recording into [session].
final class RecordingActive extends PpgRecordingState {
  /// Creates the state.
  const RecordingActive({
    required this.session,
    this.savedPackets = 0,
    this.batchesWritten = 0,
    this.lastSequence,
    this.failure,
  });

  /// Open session.
  final Session session;

  /// Packets persisted so far in this session.
  final int savedPackets;

  /// Transactions committed so far.
  final int batchesWritten;

  /// Highest sequence persisted.
  final int? lastSequence;

  /// Last write failure (recording continues).
  final Failure? failure;

  @override
  List<Object?> get props => [
    session,
    savedPackets,
    batchesWritten,
    lastSequence,
    failure,
  ];
}

/// Persists live packets into Drift in batches while a session is open.
///
/// All events go through **one** handler with the `sequential()` transformer,
/// so a batch write, a stop, and the final flush can never interleave: the
/// stop handler runs only after every previously queued batch is committed,
/// then drains what is still buffered. That is what guarantees "no loss
/// across batch boundaries".
class PpgRecordingBloc extends Bloc<PpgRecordingEvent, PpgRecordingState> {
  /// [device] supplies live packets, [recording] persists them.
  /// [maxBatchSize] / [maxBatchDelay] tune batching (50 packets / 250 ms).
  PpgRecordingBloc({
    required DeviceRepository device,
    required RecordingRepository recording,
    this.maxBatchSize = 50,
    this.maxBatchDelay = const Duration(milliseconds: 250),
  }) : _device = device,
       _recording = recording,
       super(const RecordingIdle()) {
    on<PpgRecordingEvent>(_onEvent, transformer: sequential());
  }

  final DeviceRepository _device;
  final RecordingRepository _recording;

  /// Flush after this many packets.
  final int maxBatchSize;

  /// Flush this long after the first buffered packet.
  final Duration maxBatchDelay;

  StreamSubscription<PpgPacket>? _subscription;
  Batcher<PpgPacket>? _batcher;

  /// While stopping, batches are collected here instead of being queued as
  /// events (which would run after Stop, when the session is already closed).
  List<PpgPacket>? _stopBuffer;

  Future<void> _onEvent(
    PpgRecordingEvent event,
    Emitter<PpgRecordingState> emit,
  ) => switch (event) {
    RecordingStarted(:final deviceId) => _start(deviceId, emit),
    RecordingStopped() => _stop(emit),
    _BatchReady(:final batch) => _save(batch, emit),
  };

  Future<void> _start(String deviceId, Emitter<PpgRecordingState> emit) async {
    if (state is RecordingActive) return;
    switch (await _recording.startSession(
      deviceId: deviceId,
      startedAt: clock.now(),
    )) {
      case Err(:final failure):
        emit(RecordingIdle(failure: failure));
      case Ok(value: final session):
        emit(RecordingActive(session: session));
        final batcher = _batcher = Batcher<PpgPacket>(
          maxCount: maxBatchSize,
          maxDelay: maxBatchDelay,
          onBatch: (b) => _stopBuffer != null
              ? _stopBuffer!.addAll(b)
              : add(_BatchReady(b)),
        );
        _subscription = _device.livePackets.listen(batcher.add);
    }
  }

  Future<void> _save(
    List<PpgPacket> batch,
    Emitter<PpgRecordingState> emit,
  ) async {
    final current = state;
    if (current is! RecordingActive || batch.isEmpty) return;
    final result = await _recording.savePackets(current.session.id, batch);
    final lastSeq = batch
        .map((p) => p.sequence)
        .reduce((a, b) => a > b ? a : b);
    emit(switch (result) {
      Ok(value: final inserted) => RecordingActive(
        session: current.session,
        savedPackets: current.savedPackets + inserted,
        batchesWritten: current.batchesWritten + 1,
        lastSequence:
            current.lastSequence == null || lastSeq > current.lastSequence!
            ? lastSeq
            : current.lastSequence,
      ),
      Err(:final failure) => RecordingActive(
        session: current.session,
        savedPackets: current.savedPackets,
        batchesWritten: current.batchesWritten,
        lastSequence: current.lastSequence,
        failure: failure,
      ),
    });
  }

  Future<void> _stop(Emitter<PpgRecordingState> emit) async {
    final current = state;
    if (current is! RecordingActive) return;
    _stopBuffer = [];
    // Packets emitted before Stop may still be queued as microtasks on the
    // stream; a zero timer runs after them, so nothing in flight is lost.
    await Future<void>.delayed(Duration.zero);
    await _subscription?.cancel();
    _subscription = null;
    final rest = [..._stopBuffer!, ...?_batcher?.drain()];
    _stopBuffer = null;
    _batcher = null;
    await _save(rest, emit);
    final endedAt = clock.now();
    final ended = await _recording.endSession(current.session.id, endedAt);
    emit(
      RecordingIdle(
        lastSession: Session(
          id: current.session.id,
          deviceId: current.session.deviceId,
          startedAt: current.session.startedAt,
          sampleRateHz: current.session.sampleRateHz,
          endedAt: endedAt,
        ),
        failure: ended.failureOrNull,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _batcher?.dispose();
    return super.close();
  }
}
