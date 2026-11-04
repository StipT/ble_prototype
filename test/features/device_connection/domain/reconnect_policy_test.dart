import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/features/device_connection/domain/ble_failure_mapping.dart';
import 'package:ble_prototype/features/device_connection/domain/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReconnectPolicy', () {
    test('doubles from the initial delay and caps at maxDelay', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
      );
      expect(
        [for (var i = 1; i <= 6; i++) policy.delayFor(i).inSeconds],
        [1, 2, 4, 8, 10, 10],
      );
    });

    test('huge attempt numbers stay capped (no overflow)', () {
      expect(
        const ReconnectPolicy().delayFor(500),
        const Duration(seconds: 30),
      );
    });

    test('maxAttempts limits attempts; null means forever', () {
      expect(const ReconnectPolicy(maxAttempts: 2).allows(2), isTrue);
      expect(const ReconnectPolicy(maxAttempts: 2).allows(3), isFalse);
      expect(const ReconnectPolicy().allows(1 << 30), isTrue);
    });
  });

  group('mapBleError', () {
    test('passes failures through', () {
      expect(mapBleError(const BluetoothOff()), const BluetoothOff());
    });

    test('maps platform messages to typed failures', () {
      expect(
        mapBleError(Exception('SecurityException: missing permission')),
        isA<BlePermissionDenied>(),
      );
      expect(
        mapBleError(StateError('Bluetooth adapter is powered off')),
        isA<BluetoothOff>(),
      );
      expect(mapBleError(Exception('Device not found')), isA<DeviceNotFound>());
      expect(mapBleError(Exception('GATT error 133')), isA<ConnectionLost>());
    });
  });
}
