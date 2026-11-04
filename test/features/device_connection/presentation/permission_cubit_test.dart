import 'dart:async';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_permission_service.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ble_types.dart';
import 'package:ble_prototype/features/device_connection/domain/permission_service.dart';
import 'package:ble_prototype/features/device_connection/presentation/cubit/permission_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<BluetoothAdapterStatus> adapter;
  late FakePermissionService permissions;

  setUp(() {
    adapter = StreamController<BluetoothAdapterStatus>.broadcast();
    permissions = FakePermissionService();
  });

  tearDown(() => adapter.close());

  PermissionCubit build() =>
      PermissionCubit(permissions: permissions, adapterStatus: adapter.stream);

  test('starts in PermissionChecking', () {
    expect(build().state, const PermissionChecking());
  });

  blocTest<PermissionCubit, PermissionState>(
    'granted, then follows the radio on/off',
    build: build,
    act: (cubit) async {
      await cubit.check();
      adapter.add(BluetoothAdapterStatus.poweredOff);
      await pumpEventQueue();
      adapter.add(BluetoothAdapterStatus.poweredOn);
      await pumpEventQueue();
    },
    expect: () => const [
      PermissionGranted(),
      PermissionBluetoothOff(),
      PermissionGranted(),
    ],
  );

  blocTest<PermissionCubit, PermissionState>(
    'radio state alone emits nothing until the permission is known',
    build: build,
    act: (cubit) async {
      adapter.add(BluetoothAdapterStatus.poweredOff);
      await pumpEventQueue();
      await cubit.check();
    },
    expect: () => const [PermissionBluetoothOff()],
  );

  blocTest<PermissionCubit, PermissionState>(
    'missing BLE hardware is reported as unsupported Bluetooth',
    build: build,
    act: (cubit) async {
      adapter.add(BluetoothAdapterStatus.unsupported);
      await pumpEventQueue();
      await cubit.check();
    },
    expect: () => const [PermissionBluetoothOff(unsupported: true)],
  );

  blocTest<PermissionCubit, PermissionState>(
    'denied, then granted through the dialog',
    setUp: () => permissions.status = BlePermissionStatus.denied,
    build: build,
    act: (cubit) async {
      await cubit.check();
      await cubit.request();
    },
    expect: () => const [PermissionDenied(), PermissionGranted()],
    verify: (_) => expect(permissions.requestCount, 1),
  );

  blocTest<PermissionCubit, PermissionState>(
    'denying with "don\'t ask again" becomes permanently denied',
    setUp: () => permissions
      ..status = BlePermissionStatus.denied
      ..requestOutcome = BlePermissionStatus.permanentlyDenied,
    build: build,
    act: (cubit) async {
      await cubit.check();
      await cubit.request();
    },
    expect: () => const [PermissionDenied(), PermissionPermanentlyDenied()],
  );

  blocTest<PermissionCubit, PermissionState>(
    'permanently denied: the dialog is not shown, Settings fixes it',
    setUp: () => permissions.status = BlePermissionStatus.permanentlyDenied,
    build: build,
    act: (cubit) async {
      await cubit.check();
      await cubit.request();
      await cubit.openSettings();
    },
    expect: () => const [PermissionPermanentlyDenied(), PermissionGranted()],
    verify: (_) {
      expect(permissions.requestCount, 0);
      expect(permissions.openSettingsCount, 1);
    },
  );

  blocTest<PermissionCubit, PermissionState>(
    'an "unauthorized" radio re-reads the permission',
    build: build,
    act: (cubit) async {
      await cubit.check();
      permissions.status = BlePermissionStatus.denied;
      adapter.add(BluetoothAdapterStatus.unauthorized);
      await pumpEventQueue();
    },
    expect: () => const [PermissionGranted(), PermissionDenied()],
  );

  test('states map to typed failures', () {
    expect(const PermissionGranted().failure, isNull);
    expect(const PermissionDenied().failure, const BlePermissionDenied());
    expect(
      const PermissionPermanentlyDenied().failure,
      const BlePermissionDenied.permanently(),
    );
    expect(const PermissionBluetoothOff().failure, isA<BluetoothOff>());
  });
}
