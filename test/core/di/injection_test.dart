import 'package:ble_prototype/core/config/app_config.dart';
import 'package:ble_prototype/core/di/injection.dart';
import 'package:ble_prototype/features/device_connection/data/adapters/ppg_device_adapter.dart';
import 'package:ble_prototype/features/device_connection/data/adapters/reactive_ble_ppg_device_adapter.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/device_connection/data/permission_handler_service.dart';
import 'package:ble_prototype/features/device_connection/domain/permission_service.dart';
import 'package:ble_prototype/features/pairing_nfc/data/nfc_manager_reader.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/nfc_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => sl.reset());

  test(
    'USE_FAKE_DEVICE=false / USE_FAKE_NFC=false wire real hardware',
    () async {
      await configureDependencies(
        const AppConfig(
          useFakeDevice: false,
          useFakeNfc: false,
          enableFirebase: false,
        ),
        database: testDatabase(),
      );

      expect(sl<PpgDeviceAdapter>(), isA<ReactiveBlePpgDeviceAdapter>());
      expect(sl<PermissionService>(), isA<PermissionHandlerService>());
      expect(sl<NfcReader>(), isA<NfcManagerReader>());
      expect(sl.isRegistered<FakePpgDevice>(), isFalse);
    },
  );

  test('defaults wire the simulator', () async {
    await configureDependencies(
      const AppConfig(enableFirebase: false),
      database: testDatabase(),
    );
    expect(sl<PpgDeviceAdapter>(), isA<FakePpgDevice>());
  });
}
