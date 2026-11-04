import 'package:equatable/equatable.dart';

/// Base type for every expected, recoverable error in the app.
///
/// Domain and data layers never throw for expected problems; they return a
/// `Result<T, Failure>` (see `core/result/result.dart`). Because the class is
/// `sealed`, a `switch` over a [Failure] is checked for exhaustiveness by the
/// compiler, so the UI can't silently forget to handle a new failure kind.
sealed class Failure extends Equatable {
  const Failure(this.message);

  /// Human readable, developer-oriented explanation. Not localized (non-goal).
  final String message;

  @override
  List<Object?> get props => [runtimeType, message];

  @override
  String toString() => '$runtimeType($message)';
}

/// The user (or the OS) refused one of the Bluetooth runtime permissions.
///
/// Android 12+ needs `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`; Android <= 11 needs
/// location instead; iOS needs `NSBluetoothAlwaysUsageDescription` and shows
/// its own prompt the first time CoreBluetooth is touched.
final class BlePermissionDenied extends Failure {
  const BlePermissionDenied([super.message = 'Bluetooth permission denied'])
    : permanentlyDenied = false;

  /// Denied with "don't ask again" (Android) / denied once on iOS. The app can
  /// no longer show the system dialog; only the Settings app can fix it.
  const BlePermissionDenied.permanently([
    super.message = 'Bluetooth permission permanently denied',
  ]) : permanentlyDenied = true;

  /// Whether the only way forward is opening the OS settings.
  final bool permanentlyDenied;

  @override
  List<Object?> get props => [...super.props, permanentlyDenied];
}

/// The Bluetooth radio is switched off (or unsupported / resetting).
final class BluetoothOff extends Failure {
  const BluetoothOff([super.message = 'Bluetooth is turned off']);
}

/// A scan finished without finding the requested device, or a connect attempt
/// targeted an ID that is not advertising.
final class DeviceNotFound extends Failure {
  const DeviceNotFound([super.message = 'Device not found']);
}

/// An established link dropped (out of range, device powered off, supervision
/// timeout, GATT error 133 on Android, ...).
final class ConnectionLost extends Failure {
  const ConnectionLost([super.message = 'Connection lost']);
}

/// Bytes received from the device do not match the expected packet layout.
final class ProtocolError extends Failure {
  const ProtocolError(super.message);
}

/// NFC hardware is missing, disabled, or the platform does not allow reading
/// tags (e.g. iOS simulator, iPhone without the entitlement).
final class NfcUnavailable extends Failure {
  const NfcUnavailable([super.message = 'NFC is unavailable']);
}

/// An NFC tag was read, but it does not carry a pairing record we
/// understand: not NDEF formatted, empty, or a record with a malformed
/// device ID. The user tapped the wrong tag (a transit card, a blank
/// sticker, ...) — retrying with the right tag can succeed.
final class NfcTagInvalid extends Failure {
  const NfcTagInvalid(super.message);
}

/// The NFC read session ended without a tag: the user pressed Cancel (the
/// in-app button, or the system sheet on iOS) or iOS timed the session out
/// after 60 s. Not an error worth showing in red — the UI simply returns
/// to idle.
final class NfcReadCancelled extends Failure {
  const NfcReadCancelled([super.message = 'NFC read cancelled']);
}

/// Local database read/write failed.
final class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// Remote backend (Firebase) call failed.
///
/// [retryable] separates transient problems (offline, timeout, server
/// unavailable — worth retrying with backoff) from permanent ones
/// (permission denied by the security rules, invalid document — retrying
/// the identical request can never succeed).
final class CloudFailure extends Failure {
  const CloudFailure(super.message, {this.retryable = true});

  /// Whether retrying the same request later may succeed.
  final bool retryable;

  @override
  List<Object?> get props => [...super.props, retryable];
}
