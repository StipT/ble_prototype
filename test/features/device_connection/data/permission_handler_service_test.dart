import 'package:ble_prototype/features/device_connection/data/permission_handler_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('PermissionHandlerService.requiredPermissions', () {
    test('Android 11 (API 30) and lower asks for location', () async {
      final service = PermissionHandlerService(
        platform: TargetPlatform.android,
        androidSdkInt: () async => 30,
      );
      expect(await service.requiredPermissions(), [
        Permission.locationWhenInUse,
      ]);
    });

    test('Android 12+ asks for nearby-devices permissions', () async {
      var calls = 0;
      final service = PermissionHandlerService(
        platform: TargetPlatform.android,
        androidSdkInt: () async {
          calls++;
          return 31;
        },
      );
      expect(await service.requiredPermissions(), [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]);
      await service.requiredPermissions();
      expect(calls, 1, reason: 'SDK level is cached');
    });

    test('iOS asks for Bluetooth and never queries the Android SDK', () async {
      final service = PermissionHandlerService(
        platform: TargetPlatform.iOS,
        androidSdkInt: () => throw StateError('not Android'),
      );
      expect(await service.requiredPermissions(), [Permission.bluetooth]);
    });
  });
}
