import 'package:ble_prototype/app/app.dart';
import 'package:ble_prototype/core/config/app_config.dart';
import 'package:ble_prototype/core/di/injection.dart';
import 'package:ble_prototype/core/storage/in_memory_storage.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/pairing_nfc/data/fake/fake_nfc_reader.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/nfc_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  tearDown(() => sl.reset());

  Future<void> setUpApp(WidgetTester tester, InMemoryStorage storage) async {
    await configureDependencies(
      const AppConfig(enableFirebase: false),
      database: testDatabase(),
      hydratedStorage: storage,
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    sl<FakePpgDevice>().dispose();
    (sl<NfcReader>() as FakeNfcReader).dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  String phase(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('connection-phase'))).data!;

  testWidgets('tap to pair connects, then Reconnect / Forget after restart', (
    tester,
  ) async {
    final storage = InMemoryStorage();
    await setUpApp(tester, storage);
    await tester.pumpWidget(const PpgApp());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('last-paired')), findsNothing);
    await tester.tap(find.byKey(const Key('nfc-pair-button')));
    await tester.pump();
    expect(find.byKey(const Key('nfc-cancel-button')), findsOneWidget);

    // FakeNfcReader "taps" after 1.5 s; the connection bloc takes over.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(phase(tester), 'Connecting…');
    await tester.pump(const Duration(seconds: 1));
    expect(phase(tester), 'Connected');
    expect(find.text('Last paired: PPG-Fake-0001'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('reconnect-button')))
          .onPressed,
      isNull,
      reason: 'disabled while connected',
    );
    await tearDownApp(tester);

    // "Restart": fresh DI and widgets, same persisted storage.
    await sl.reset();
    await setUpApp(tester, storage);
    await tester.pumpWidget(const PpgApp());
    await tester.pump();
    await tester.pump();
    expect(phase(tester), 'Not connected');
    expect(find.text('Last paired: PPG-Fake-0001'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reconnect-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(tester), 'Connected');

    await tester.tap(find.byKey(const Key('forget-button')));
    await tester.pump();
    expect(find.byKey(const Key('last-paired')), findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('NFC unsupported falls back to scanning', (tester) async {
    await setUpApp(tester, InMemoryStorage());
    (sl<NfcReader>() as FakeNfcReader).status = NfcStatus.unsupported;
    await tester.pumpWidget(const PpgApp());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('nfc-pair-button')), findsNothing);
    expect(find.textContaining('Use Scan below'), findsOneWidget);
    expect(find.byKey(const Key('scan-button')), findsOneWidget);
    await tearDownApp(tester);
  });
}
