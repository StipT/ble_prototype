import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/ble_types.dart';
import '../../domain/permission_service.dart';

/// States of [PermissionCubit]: can the app use BLE right now?
sealed class PermissionState extends Equatable {
  const PermissionState();

  /// The [Failure] that explains why BLE is blocked, `null` when it isn't.
  Failure? get failure => null;

  @override
  List<Object?> get props => [];
}

/// Permission status not read yet.
final class PermissionChecking extends PermissionState {
  /// Creates the state.
  const PermissionChecking();
}

/// Permissions granted and the radio is on: scanning may start.
final class PermissionGranted extends PermissionState {
  /// Creates the state.
  const PermissionGranted();
}

/// The user refused, but the system dialog may be shown again
/// (call [PermissionCubit.request]).
final class PermissionDenied extends PermissionState {
  /// Creates the state.
  const PermissionDenied();

  @override
  Failure get failure => const BlePermissionDenied();
}

/// The OS will not show the dialog anymore; only Settings can fix it
/// (call [PermissionCubit.openSettings]).
final class PermissionPermanentlyDenied extends PermissionState {
  /// Creates the state.
  const PermissionPermanentlyDenied();

  @override
  Failure get failure => const BlePermissionDenied.permanently();
}

/// Permissions are fine but the phone's Bluetooth radio is off (or the
/// hardware has no BLE). Apps cannot switch it on silently: Android 13+
/// removed `BluetoothAdapter.enable()` for normal apps and iOS never had an
/// API — the user must use quick settings / Control Center.
final class PermissionBluetoothOff extends PermissionState {
  /// [unsupported] is true when the device has no BLE at all (e.g. the iOS
  /// simulator), so turning Bluetooth on cannot help.
  const PermissionBluetoothOff({this.unsupported = false});

  /// Whether BLE hardware is missing rather than switched off.
  final bool unsupported;

  @override
  Failure get failure => BluetoothOff(
    unsupported
        ? 'Bluetooth Low Energy is not supported on this device'
        : 'Bluetooth is turned off',
  );

  @override
  List<Object?> get props => [unsupported];
}

/// Gatekeeper for everything BLE: combines the runtime permission
/// ([PermissionService]) with the radio state (`adapterStatus`) into one
/// state the UI can switch over.
///
/// A `Cubit` fits: there are only a few imperative commands ([check],
/// [request], [openSettings]) and no event transformations to express.
///
/// Call [check] at start-up and whenever the app is resumed — users often
/// leave for Settings and come back with a changed permission, and neither
/// platform notifies the app about that.
class PermissionCubit extends Cubit<PermissionState> {
  /// [permissions] talks to the OS; [adapterStatus] is the phone radio state
  /// stream (current value first, e.g. `DeviceRepository.adapterStatus`).
  PermissionCubit({
    required PermissionService permissions,
    required Stream<BluetoothAdapterStatus> adapterStatus,
  }) : _permissions = permissions,
       super(const PermissionChecking()) {
    _adapterSubscription = adapterStatus.listen((status) {
      _adapter = status;
      if (status == BluetoothAdapterStatus.unauthorized) {
        // The radio itself reports a revoked permission: re-read it.
        unawaited(check());
      } else {
        _emitDerived();
      }
    }, onError: addError);
  }

  final PermissionService _permissions;
  late final StreamSubscription<BluetoothAdapterStatus> _adapterSubscription;
  BlePermissionStatus? _permission;
  BluetoothAdapterStatus _adapter = BluetoothAdapterStatus.unknown;

  /// Re-reads the permission without prompting.
  Future<void> check() async {
    _permission = await _permissions.check();
    _emitDerived();
  }

  /// Shows the system dialog (if still allowed) and updates the state.
  Future<void> request() async {
    _permission = await _permissions.request();
    _emitDerived();
  }

  /// Opens the app's OS settings page, then re-checks. With the fake
  /// service the change is immediate; on a phone the user is still in
  /// Settings, so [check] must run again when the app resumes.
  Future<void> openSettings() async {
    await _permissions.openSettings();
    await check();
  }

  void _emitDerived() {
    final permission = _permission;
    if (permission == null || isClosed) return;
    emit(switch (permission) {
      BlePermissionStatus.denied => const PermissionDenied(),
      BlePermissionStatus.permanentlyDenied =>
        const PermissionPermanentlyDenied(),
      BlePermissionStatus.granted => switch (_adapter) {
        BluetoothAdapterStatus.poweredOff => const PermissionBluetoothOff(),
        BluetoothAdapterStatus.unsupported => const PermissionBluetoothOff(
          unsupported: true,
        ),
        // The radio says "unauthorized" although the permission reads as
        // granted (happens briefly on iOS right after a change).
        BluetoothAdapterStatus.unauthorized => const PermissionDenied(),
        // `unknown` means the BLE stack is still booting — not "off".
        BluetoothAdapterStatus.unknown ||
        BluetoothAdapterStatus.poweredOn => const PermissionGranted(),
      },
    });
  }

  @override
  Future<void> close() async {
    await _adapterSubscription.cancel();
    return super.close();
  }
}
