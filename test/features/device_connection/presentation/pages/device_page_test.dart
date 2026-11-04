import 'package:ble_prototype/app/app.dart';
import 'package:ble_prototype/core/config/app_config.dart';
import 'package:ble_prototype/core/di/injection.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_permission_service.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/device_connection/domain/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/test_database.dart';

void main() {
  tearDown(() => sl.reset());

  Future<void> setUpApp(WidgetTester tester) async {
    await configureDependencies(
      const AppConfig(enableFirebase: false),
      database: testDatabase(),
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    sl<FakePpgDevice>().dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  String phase(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('connection-phase'))).data!;

  testWidgets('scan, connect, battery, drop and auto-reconnect', (
    tester,
  ) async {
    await setUpApp(tester);
    await tester.pumpWidget(const PpgApp());
    await tester.pump();

    expect(phase(tester), 'Not connected');
    await tester.tap(find.byKey(const Key('scan-button')));
    await tester.pump();
    expect(phase(tester), 'Scanning…');
    await tester.pump(const Duration(seconds: 5));

    final connect = find.byKey(
      const Key('connect-${FakePpgDevice.defaultDeviceId}'),
    );
    expect(connect, findsOneWidget);
    await tester.tap(connect);
    await tester.pump();
    expect(phase(tester), 'Connecting…');
    await tester.pump(const Duration(seconds: 1));

    expect(phase(tester), 'Connected');
    expect(find.byKey(const Key('battery-text')), findsOneWidget);
    expect(find.textContaining('Battery: 100%'), findsOneWidget);
    expect(sl<FakePpgDevice>().isStreaming, isTrue);

    // Debug panel: force a link drop.
    await tester.tap(find.text('Debug fault panel (fake device)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('fault-disconnect')));
    await tester.pump();
    await tester.pump();
    expect(phase(tester), 'Reconnecting (attempt 1) in 1.0 s');
    expect(sl<FakePpgDevice>().isStreaming, isFalse);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(phase(tester), 'Connected');
    // startStreaming was sent again after the reconnect.
    expect(sl<FakePpgDevice>().isStreaming, isTrue);

    await tester.tap(find.byKey(const Key('disconnect-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(phase(tester), 'Not connected');

    await tearDownApp(tester);
  });

  testWidgets('permission gate: denied → grant', (tester) async {
    await setUpApp(tester);
    final permissions = sl<PermissionService>() as FakePermissionService
      ..status = BlePermissionStatus.denied;
    await tester.pumpWidget(const PpgApp());
    await tester.pump();

    expect(find.byKey(const Key('scan-button')), findsNothing);
    await tester.tap(find.byKey(const Key('grant-permission-button')));
    await tester.pump();
    expect(permissions.requestCount, 1);
    expect(find.byKey(const Key('scan-button')), findsOneWidget);

    await tearDownApp(tester);
  });

  testWidgets('Bluetooth off from the debug panel blocks scanning', (
    tester,
  ) async {
    await setUpApp(tester);
    await tester.pumpWidget(const PpgApp());
    await tester.pump();

    await tester.tap(find.text('Debug fault panel (fake device)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('fault-bluetooth')));
    await tester.pump();
    expect(find.textContaining('Bluetooth is off'), findsOneWidget);
    expect(find.byKey(const Key('scan-button')), findsNothing);

    await tester.tap(find.byKey(const Key('fault-bluetooth')));
    await tester.pump();
    expect(find.byKey(const Key('scan-button')), findsOneWidget);

    await tearDownApp(tester);
  });
}
