import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/ble_failure_mapping.dart';
import '../../domain/device_repository.dart';
import '../../domain/entities/ble_types.dart';
import '../../domain/entities/device_status.dart';
import '../../domain/reconnect_policy.dart';

/// Waits for [delay]. Injected into [DeviceConnectionBloc] so tests can
/// record the requested backoff delays instead of really waiting.
typedef Sleeper = Future<void> Function(Duration delay);

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------

/// Events of [DeviceConnectionBloc].
sealed class DeviceConnectionEvent extends Equatable {
  const DeviceConnectionEvent();

  @override
  List<Object?> get props => [];
}

/// User pressed "Scan": listen for advertisements for [timeout].
///
/// BLE discovery is passive: peripherals broadcast small *advertising
/// packets* (name, service UUIDs, ...) every 20 ms–10 s and the phone just
/// listens. Scans drain the battery, so they are always time-boxed; Android
/// additionally throttles apps that start more than 5 scans per 30 s.
final class DeviceScanRequested extends DeviceConnectionEvent {
  /// [timeout] is how long to listen.
  const DeviceScanRequested({this.timeout = const Duration(seconds: 4)});

  /// Scan duration.
  final Duration timeout;

  @override
  List<Object?> get props => [timeout];
}

/// Commands that change the link. They share one `restartable()` handler, so
/// a newer command (e.g. Disconnect) cancels an older one that is still
/// running (e.g. a reconnect loop sleeping between attempts).
sealed class DeviceLinkCommand extends DeviceConnectionEvent {
  const DeviceLinkCommand();
}

/// User picked a device to connect to.
final class DeviceConnectRequested extends DeviceLinkCommand {
  /// [deviceId] is the OS identifier from the scan (MAC on Android, a
  /// per-phone UUID on iOS).
  const DeviceConnectRequested(this.deviceId);

  /// Device to connect to.
  final String deviceId;

  @override
  List<Object?> get props => [deviceId];
}

/// User pressed "Disconnect": drop the link and stop auto-reconnecting.
final class DeviceDisconnectRequested extends DeviceLinkCommand {
  /// Creates the event.
  const DeviceDisconnectRequested();
}

/// Internal: the link dropped unexpectedly; start the backoff loop.
final class _ReconnectRequested extends DeviceLinkCommand {
  const _ReconnectRequested();
}

/// Internal: link-state notification from the repository.
final class _LinkStateChanged extends DeviceConnectionEvent {
  const _LinkStateChanged(this.linkState);

  final DeviceLinkState linkState;

  @override
  List<Object?> get props => [linkState];
}

/// Internal: battery/status notification from the device.
final class _StatusReceived extends DeviceConnectionEvent {
  const _StatusReceived(this.status);

  final DeviceStatus status;

  @override
  List<Object?> get props => [status];
}

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

/// What the connection flow is doing.
enum ConnectionPhase {
  /// No link and nothing in progress.
  idle,

  /// Listening for advertisements.
  scanning,

  /// First connect attempt (connect → MTU → clock sync → start streaming).
  connecting,

  /// Link up and streaming.
  connected,

  /// The link dropped; retrying with backoff.
  reconnecting,

  /// User-requested disconnect in progress.
  disconnecting,
}

/// State of [DeviceConnectionBloc]. A single class (not a sealed family)
/// because most fields — target device, last scan, last failure — survive
/// across phases and the UI shows them side by side.
final class DeviceConnectionState extends Equatable {
  /// Creates the state.
  const DeviceConnectionState({
    this.phase = ConnectionPhase.idle,
    this.devices = const [],
    this.deviceId,
    this.status,
    this.failure,
    this.reconnectAttempt = 0,
    this.nextRetryIn,
  });

  /// Current phase.
  final ConnectionPhase phase;

  /// Result of the last scan, strongest signal first.
  final List<DiscoveredPpgDevice> devices;

  /// Device the user chose (kept while reconnecting).
  final String? deviceId;

  /// Latest battery/status snapshot, `null` while not connected.
  final DeviceStatus? status;

  /// Last error (scan, connect or reconnect attempt).
  final Failure? failure;

  /// 1-based number of the current reconnect attempt, 0 when not
  /// reconnecting.
  final int reconnectAttempt;

  /// Backoff delay before the current reconnect attempt; `null` once the
  /// attempt itself is running.
  final Duration? nextRetryIn;

  /// Whether the link is up.
  bool get isConnected => phase == ConnectionPhase.connected;

  /// Copy with changes. Nullable fields take a closure so they can be reset
  /// to `null` (e.g. `failure: () => null`).
  DeviceConnectionState copyWith({
    ConnectionPhase? phase,
    List<DiscoveredPpgDevice>? devices,
    String? Function()? deviceId,
    DeviceStatus? Function()? status,
    Failure? Function()? failure,
    int? reconnectAttempt,
    Duration? Function()? nextRetryIn,
  }) => DeviceConnectionState(
    phase: phase ?? this.phase,
    devices: devices ?? this.devices,
    deviceId: deviceId != null ? deviceId() : this.deviceId,
    status: status != null ? status() : this.status,
    failure: failure != null ? failure() : this.failure,
    reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    nextRetryIn: nextRetryIn != null ? nextRetryIn() : this.nextRetryIn,
  );

  @override
  List<Object?> get props => [
    phase,
    devices,
    deviceId,
    status,
    failure,
    reconnectAttempt,
    nextRetryIn,
  ];
}

// -----------------------------------------------------------------------------
// Bloc
// -----------------------------------------------------------------------------

/// Scan → connect → stream → (drop → reconnect with backoff) lifecycle.
///
/// Key BLE facts this bloc encodes:
/// * A GATT link can drop at any time (out of range, device reset, Android
///   "GATT 133", iOS supervision timeout). Only drops the user did *not*
///   ask for trigger [ReconnectPolicy]-driven retries.
/// * After every (re)connect the device is a blank slate for this link:
///   notifications must be re-enabled and the start command sent again, so
///   `startStreaming` is always written after a successful connect. (The
///   repository's connect also renegotiates the MTU and resyncs the clock.)
/// * The device keeps storing samples while disconnected; the history sync
///   (issue 04) fetches the gap, this bloc only restores the link.
///
/// Concurrency: link commands use `restartable()` — the newest command wins
/// and the older handler's `emit` is cancelled, which is how Disconnect
/// stops a reconnect loop. Scans use `droppable()` so double taps are
/// ignored while a scan runs.
class DeviceConnectionBloc
    extends Bloc<DeviceConnectionEvent, DeviceConnectionState> {
  /// [device] is the domain repository; [policy] controls the reconnect
  /// backoff; [sleeper] waits between attempts (defaults to a cancellable
  /// timer — tests inject one that records the delays and returns at once).
  DeviceConnectionBloc({
    required DeviceRepository device,
    this.policy = const ReconnectPolicy(),
    Sleeper? sleeper,
  }) : _device = device,
       _sleeper = sleeper,
       super(const DeviceConnectionState()) {
    on<DeviceScanRequested>(_onScan, transformer: droppable());
    on<DeviceLinkCommand>(_onLinkCommand, transformer: restartable());
    on<_LinkStateChanged>(_onLinkStateChanged);
    on<_StatusReceived>(_onStatusReceived);

    _linkSubscription = _device.linkState.listen(
      (s) => add(_LinkStateChanged(s)),
      onError: addError,
    );
    _statusSubscription = _device.statusUpdates.listen(
      (s) => add(_StatusReceived(s)),
      onError: addError,
    );
  }

  final DeviceRepository _device;
  final Sleeper? _sleeper;

  /// Backoff configuration for automatic reconnects.
  final ReconnectPolicy policy;

  late final StreamSubscription<DeviceLinkState> _linkSubscription;
  late final StreamSubscription<DeviceStatus> _statusSubscription;
  final Map<Timer, Completer<void>> _sleeps = {};
  bool _closing = false;

  Future<void> _onScan(
    DeviceScanRequested event,
    Emitter<DeviceConnectionState> emit,
  ) async {
    if (state.phase != ConnectionPhase.idle) return;
    emit(
      state.copyWith(
        phase: ConnectionPhase.scanning,
        devices: const [],
        failure: () => null,
      ),
    );
    final result = await _guard(() => _device.scan(timeout: event.timeout));
    // A connect may have started meanwhile; don't overwrite its phase.
    final phase = state.phase == ConnectionPhase.scanning
        ? ConnectionPhase.idle
        : state.phase;
    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(
            phase: phase,
            devices: value,
            failure: () => value.isEmpty
                ? const DeviceNotFound('No PPG device found nearby')
                : null,
          ),
        );
      case Err(:final failure):
        emit(state.copyWith(phase: phase, failure: () => failure));
    }
  }

  Future<void> _onLinkCommand(
    DeviceLinkCommand event,
    Emitter<DeviceConnectionState> emit,
  ) => switch (event) {
    DeviceConnectRequested(:final deviceId) => _connect(deviceId, emit),
    DeviceDisconnectRequested() => _disconnect(emit),
    _ReconnectRequested() => _reconnect(emit),
  };

  Future<void> _connect(
    String deviceId,
    Emitter<DeviceConnectionState> emit,
  ) async {
    emit(
      state.copyWith(
        phase: ConnectionPhase.connecting,
        deviceId: () => deviceId,
        status: () => null,
        failure: () => null,
        reconnectAttempt: 0,
        nextRetryIn: () => null,
      ),
    );
    final result = await _connectAndStart(deviceId);
    if (emit.isDone) return _abandon(result);
    switch (result) {
      case Ok(:final value):
        _enterConnected(value, emit);
      case Err(:final failure):
        emit(
          state.copyWith(phase: ConnectionPhase.idle, failure: () => failure),
        );
    }
  }

  Future<void> _reconnect(Emitter<DeviceConnectionState> emit) async {
    final deviceId = state.deviceId;
    if (deviceId == null) return;
    emit(
      state.copyWith(
        phase: ConnectionPhase.reconnecting,
        status: () => null,
        failure: () => const ConnectionLost(),
      ),
    );
    for (var attempt = 1; ; attempt++) {
      if (!policy.allows(attempt)) {
        emit(
          state.copyWith(
            phase: ConnectionPhase.idle,
            reconnectAttempt: 0,
            nextRetryIn: () => null,
            failure: () => ConnectionLost(
              'Gave up after ${attempt - 1} reconnect attempts',
            ),
          ),
        );
        return;
      }
      final delay = policy.delayFor(attempt);
      emit(state.copyWith(reconnectAttempt: attempt, nextRetryIn: () => delay));
      await _sleep(delay);
      if (emit.isDone || _closing) return;
      emit(state.copyWith(nextRetryIn: () => null));

      final result = await _connectAndStart(deviceId);
      if (emit.isDone) return _abandon(result);
      switch (result) {
        case Ok(:final value):
          _enterConnected(value, emit);
          return;
        case Err(:final failure):
          emit(state.copyWith(failure: () => failure));
      }
    }
  }

  Future<void> _disconnect(Emitter<DeviceConnectionState> emit) async {
    // Set the phase *before* disconnecting so the resulting link-state
    // notification is recognized as intentional (no auto-reconnect).
    emit(
      state.copyWith(
        phase: ConnectionPhase.disconnecting,
        reconnectAttempt: 0,
        nextRetryIn: () => null,
      ),
    );
    await _device.disconnect();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        phase: ConnectionPhase.idle,
        status: () => null,
        failure: () => null,
      ),
    );
  }

  void _onLinkStateChanged(
    _LinkStateChanged event,
    Emitter<DeviceConnectionState> emit,
  ) {
    if (event.linkState == DeviceLinkState.disconnected &&
        state.phase == ConnectionPhase.connected) {
      add(const _ReconnectRequested());
    }
  }

  void _onStatusReceived(
    _StatusReceived event,
    Emitter<DeviceConnectionState> emit,
  ) {
    if (state.isConnected) emit(state.copyWith(status: () => event.status));
  }

  /// connect (MTU + clock sync inside the repository) → start streaming →
  /// initial status read. A failed status *read* is not fatal: status
  /// notifications will fill it in shortly.
  Future<Result<DeviceStatus?, Failure>> _connectAndStart(String deviceId) =>
      _guard(() async {
        final connected = await _device.connect(deviceId);
        if (connected case Err(:final failure)) return Err(failure);
        final started = await _device.startStreaming();
        if (started case Err(:final failure)) return Err(failure);
        final status = await _device.readStatus();
        return Ok(status.valueOrNull);
      });

  void _enterConnected(
    DeviceStatus? status,
    Emitter<DeviceConnectionState> emit,
  ) {
    emit(
      state.copyWith(
        phase: ConnectionPhase.connected,
        status: () => status,
        failure: () => null,
        reconnectAttempt: 0,
        nextRetryIn: () => null,
      ),
    );
    // The link may have dropped between connect and now; that notification
    // was ignored because we weren't "connected" yet.
    if (_device.currentLinkState != DeviceLinkState.connected) {
      add(const _ReconnectRequested());
    }
  }

  /// A newer command superseded a connect attempt that still succeeded. If
  /// the user meanwhile asked to disconnect, honour that.
  void _abandon(Result<Object?, Failure> result) {
    if (result.isOk &&
        (state.phase == ConnectionPhase.idle ||
            state.phase == ConnectionPhase.disconnecting)) {
      unawaited(_device.disconnect());
    }
  }

  Future<void> _sleep(Duration delay) {
    final sleeper = _sleeper;
    if (sleeper != null) return sleeper(delay);
    final completer = Completer<void>();
    late final Timer timer;
    timer = Timer(delay, () {
      _sleeps.remove(timer);
      completer.complete();
    });
    _sleeps[timer] = completer;
    return completer.future;
  }

  static Future<Result<T, Failure>> _guard<T>(
    Future<Result<T, Failure>> Function() body,
  ) async {
    try {
      return await body();
    } on Object catch (e) {
      return Err(mapBleError(e));
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    for (final MapEntry(key: timer, value: completer) in _sleeps.entries) {
      timer.cancel();
      completer.complete();
    }
    _sleeps.clear();
    await _linkSubscription.cancel();
    await _statusSubscription.cancel();
    return super.close();
  }
}
