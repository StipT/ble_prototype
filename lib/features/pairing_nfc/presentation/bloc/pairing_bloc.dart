import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/paired_device.dart';
import '../../domain/nfc_reader.dart';

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------

/// Input to [PairingBloc].
sealed class PairingEvent extends Equatable {
  const PairingEvent();

  @override
  List<Object?> get props => [];
}

/// Page opened / app resumed: (re)check whether NFC can be used. NFC can be
/// switched on/off in Android settings while the app is in background.
final class PairingAvailabilityChecked extends PairingEvent {
  /// Creates the event.
  const PairingAvailabilityChecked();
}

/// User pressed "Tap to pair": start an NFC session and wait for a tag.
final class PairingTapRequested extends PairingEvent {
  /// Creates the event.
  const PairingTapRequested();
}

/// User pressed "Cancel" while waiting for a tag.
final class PairingTapCancelled extends PairingEvent {
  /// Creates the event.
  const PairingTapCancelled();
}

/// User pressed "Reconnect" on the remembered device.
final class PairingReconnectRequested extends PairingEvent {
  /// Creates the event.
  const PairingReconnectRequested();
}

/// User pressed "Forget": drop the remembered device.
final class PairingForgotten extends PairingEvent {
  /// Creates the event.
  const PairingForgotten();
}

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

/// What the NFC pairing flow is doing.
enum PairingPhase {
  /// Nothing in progress.
  idle,

  /// NFC session open, waiting for the user to hold the phone to the tag.
  waitingForTag,
}

/// State of [PairingBloc].
///
/// Only [lastPaired] is persisted (see [PairingBloc.toJson]): availability
/// must be re-checked on every start, and a stale "waiting for tag" or
/// error must never come back after a restart.
final class PairingState extends Equatable {
  /// Creates the state.
  const PairingState({
    this.phase = PairingPhase.idle,
    this.nfcStatus,
    this.lastPaired,
    this.failure,
  });

  /// Current phase.
  final PairingPhase phase;

  /// Result of the last availability check; `null` until checked.
  final NfcStatus? nfcStatus;

  /// Device remembered from the last successful tap (survives restarts).
  final PairedDevice? lastPaired;

  /// Last error to show (unavailable, invalid tag). Cancellation is not an
  /// error and leaves this `null`.
  final Failure? failure;

  /// Whether "Tap to pair" can be offered. While unknown (`null`) the UI
  /// shows the button disabled; `disabled`/`unsupported` fall back to scan.
  bool get canUseNfc => nfcStatus == NfcStatus.available;

  /// Copy with changes; nullable fields take a closure so they can be reset.
  PairingState copyWith({
    PairingPhase? phase,
    NfcStatus? Function()? nfcStatus,
    PairedDevice? Function()? lastPaired,
    Failure? Function()? failure,
  }) => PairingState(
    phase: phase ?? this.phase,
    nfcStatus: nfcStatus != null ? nfcStatus() : this.nfcStatus,
    lastPaired: lastPaired != null ? lastPaired() : this.lastPaired,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [phase, nfcStatus, lastPaired, failure];
}

// -----------------------------------------------------------------------------
// Bloc
// -----------------------------------------------------------------------------

/// Hands a BLE device ID to the connection flow (wired to
/// `DeviceConnectionBloc.add(DeviceConnectRequested(id))` in `app.dart`).
typedef ConnectDevice = void Function(String deviceId);

/// NFC tap-to-pair: read a tag → remember the device → ask the connection
/// flow to connect. Remembers the last paired device across restarts.
///
/// ## Why a `HydratedBloc`
/// `HydratedBloc` serializes the state with [toJson] after every change and
/// restores it with [fromJson] in the constructor, using a key-value
/// [Storage] (on disk: `HydratedStorage`, a Hive box built in `main()`
/// under the app-support directory; in tests: `InMemoryStorage`). That's
/// exactly "remember the last paired device" with no repository or table.
/// Restoring is synchronous, so the first frame already shows "Reconnect".
///
/// ## Flow and concurrency
/// * Tap uses `droppable()`: double taps while a session is open are
///   ignored (iOS allows only one NFC session anyway).
/// * Cancel is a separate handler so it runs *while* the tap handler awaits
///   the reader; it stops the session, which completes the pending read
///   with `NfcReadCancelled`.
/// * `NfcUnavailable` (NFC off / unsupported / session refused) sets
///   [PairingState.failure] and updates [PairingState.nfcStatus], so the UI
///   hides the NFC button and points to BLE scanning instead.
/// * The bloc doesn't depend on `DeviceConnectionBloc`; it calls an
///   injected [ConnectDevice] so both stay independently testable.
class PairingBloc extends HydratedBloc<PairingEvent, PairingState> {
  /// Creates the bloc.
  ///
  /// [reader] talks to NFC (real or fake); [connectDevice] starts the BLE
  /// connection for an ID; [storage] overrides the global
  /// `HydratedBloc.storage` (DI and tests pass one explicitly); [clock]
  /// timestamps `PairedDevice.pairedAt` (tests pass a fixed one).
  PairingBloc({
    required NfcReader reader,
    required ConnectDevice connectDevice,
    Storage? storage,
    Clock clock = const Clock(),
  }) : _reader = reader,
       _connectDevice = connectDevice,
       _clock = clock,
       super(const PairingState(), storage: storage) {
    on<PairingAvailabilityChecked>(_onCheck, transformer: droppable());
    on<PairingTapRequested>(_onTap, transformer: droppable());
    on<PairingTapCancelled>(_onCancel);
    on<PairingReconnectRequested>(_onReconnect);
    on<PairingForgotten>(_onForget);
  }

  final NfcReader _reader;
  final ConnectDevice _connectDevice;
  final Clock _clock;

  Future<void> _onCheck(
    PairingAvailabilityChecked event,
    Emitter<PairingState> emit,
  ) async {
    final status = await _reader.checkAvailability();
    emit(
      state.copyWith(
        nfcStatus: () => status,
        // A previous "NFC is off" is stale once it is back on.
        failure:
            status == NfcStatus.available && state.failure is NfcUnavailable
            ? () => null
            : null,
      ),
    );
  }

  Future<void> _onTap(
    PairingTapRequested event,
    Emitter<PairingState> emit,
  ) async {
    emit(
      state.copyWith(phase: PairingPhase.waitingForTag, failure: () => null),
    );
    final result = await _reader.readPairingTag();
    switch (result) {
      case Ok(:final value):
        final device = PairedDevice.fromTag(value, _clock.now());
        emit(
          state.copyWith(
            phase: PairingPhase.idle,
            nfcStatus: () => NfcStatus.available,
            lastPaired: () => device,
          ),
        );
        _connectDevice(device.deviceId);
      case Err(failure: NfcReadCancelled()):
        emit(state.copyWith(phase: PairingPhase.idle));
      case Err(failure: final NfcUnavailable failure):
        // Re-check so the UI learns *why* (off vs unsupported).
        final status = await _reader.checkAvailability();
        emit(
          state.copyWith(
            phase: PairingPhase.idle,
            nfcStatus: () => status,
            failure: () => failure,
          ),
        );
      case Err(:final failure):
        emit(state.copyWith(phase: PairingPhase.idle, failure: () => failure));
    }
  }

  Future<void> _onCancel(
    PairingTapCancelled event,
    Emitter<PairingState> emit,
  ) => _reader.cancel();

  void _onReconnect(
    PairingReconnectRequested event,
    Emitter<PairingState> emit,
  ) {
    if (state.lastPaired case final device?) _connectDevice(device.deviceId);
  }

  void _onForget(PairingForgotten event, Emitter<PairingState> emit) =>
      emit(state.copyWith(lastPaired: () => null, failure: () => null));

  /// Persists only the remembered device.
  @override
  Map<String, dynamic>? toJson(PairingState state) => {
    'lastPaired': state.lastPaired?.toJson(),
  };

  /// Restores the remembered device; corrupt data is ignored (returning
  /// `null` makes HydratedBloc fall back to the initial state) rather than
  /// crashing the app on start-up.
  @override
  PairingState? fromJson(Map<String, dynamic> json) {
    try {
      final raw = json['lastPaired'];
      return PairingState(
        lastPaired: raw == null
            ? null
            : PairedDevice.fromJson(Map<String, dynamic>.from(raw as Map)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    await _reader.cancel();
    return super.close();
  }
}
