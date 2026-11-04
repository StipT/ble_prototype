import '../../../core/error/failures.dart';

/// Converts anything thrown by the BLE stack into a typed [Failure].
///
/// The repository already returns `Result`s for expected problems, but
/// platform plugins can still throw (`PlatformException`, `StateError`,
/// generic GATT exceptions with only a message). Native messages are not
/// standardized, so this is a best-effort keyword match:
/// * "permission", "unauthorized", "not authorized" → [BlePermissionDenied]
///   (Android throws `SecurityException` when `BLUETOOTH_CONNECT` is
///   missing; iOS reports `CBManagerState.unauthorized`).
/// * "powered off", "bluetooth is off", "disabled" → [BluetoothOff].
/// * "not found", "no device", "unknown device" → [DeviceNotFound].
/// * everything else → [ConnectionLost] (the safe, retryable default).
///
/// [error] is returned unchanged when it already is a [Failure].
Failure mapBleError(Object error) {
  if (error is Failure) return error;
  final text = error.toString().toLowerCase();
  bool has(List<String> words) => words.any(text.contains);
  if (has(['permission', 'unauthorized', 'not authorized'])) {
    return BlePermissionDenied(error.toString());
  }
  if (has(['powered off', 'poweredoff', 'bluetooth is off', 'disabled'])) {
    return BluetoothOff(error.toString());
  }
  if (has(['not found', 'no device', 'unknown device'])) {
    return DeviceNotFound(error.toString());
  }
  return ConnectionLost(error.toString());
}
