import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../device_connection/domain/device_repository.dart';
import '../../../device_connection/domain/entities/ppg_packet.dart';

/// Events of [LiveWaveformBloc].
sealed class LiveWaveformEvent extends Equatable {
  const LiveWaveformEvent();

  @override
  List<Object?> get props => [];
}

/// Start (or restart) following the live packet stream.
final class LiveWaveformSubscriptionRequested extends LiveWaveformEvent {
  /// Creates the event.
  const LiveWaveformSubscriptionRequested();
}

/// Rolling window of the most recent samples for drawing.
///
/// Reads the in-memory live stream (not the DB) because the waveform needs
/// ~10 updates/s with sub-100 ms latency; the database is the source of
/// truth for everything else.
final class LiveWaveformState extends Equatable {
  /// Creates the state.
  const LiveWaveformState({
    this.samples = const [],
    this.lastSequence,
    this.packetCount = 0,
    this.gapPackets = 0,
  });

  /// Most recent samples, oldest first, at most `LiveWaveformBloc.window`.
  final List<int> samples;

  /// Sequence number of the last live packet seen.
  final int? lastSequence;

  /// Live packets received.
  final int packetCount;

  /// Packets missing between consecutive live packets (dropped
  /// notifications). They are filled later by history sync.
  final int gapPackets;

  @override
  List<Object?> get props => [samples, lastSequence, packetCount, gapPackets];
}

/// Keeps the last [window] samples of the live PPG stream.
///
/// Showcases `emit.forEach` (stream → states, cancelled automatically when
/// the bloc closes) and the `restartable()` transformer (a second
/// subscription request cancels the first instead of stacking listeners).
class LiveWaveformBloc extends Bloc<LiveWaveformEvent, LiveWaveformState> {
  /// [repository] provides the live packets; [window] is the number of
  /// samples kept (250 = 5 s at 50 Hz).
  LiveWaveformBloc({required DeviceRepository repository, this.window = 250})
    : _repository = repository,
      super(const LiveWaveformState()) {
    on<LiveWaveformSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
  }

  final DeviceRepository _repository;

  /// Samples kept for drawing.
  final int window;

  Future<void> _onSubscriptionRequested(
    LiveWaveformSubscriptionRequested event,
    Emitter<LiveWaveformState> emit,
  ) => emit.forEach<PpgPacket>(
    _repository.livePackets,
    onData: (packet) {
      final last = state.lastSequence;
      final gap = last != null && packet.sequence > last + 1
          ? packet.sequence - last - 1
          : 0;
      final merged = [...state.samples, ...packet.samples];
      return LiveWaveformState(
        samples: merged.length > window
            ? merged.sublist(merged.length - window)
            : merged,
        lastSequence: packet.sequence,
        packetCount: state.packetCount + 1,
        gapPackets: state.gapPackets + gap,
      );
    },
  );
}
