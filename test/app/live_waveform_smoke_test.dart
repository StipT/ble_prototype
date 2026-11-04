import 'package:ble_prototype/app/app.dart';
import 'package:ble_prototype/core/config/app_config.dart';
import 'package:ble_prototype/core/di/injection.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/device_connection/domain/device_repository.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/widgets/waveform_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  tearDown(() => sl.reset());

  testWidgets('waveform animates from the fake device', (tester) async {
    await configureDependencies(
      const AppConfig(enableFirebase: false),
      database: testDatabase(),
    );
    final repo = sl<DeviceRepository>();

    await tester.pumpWidget(const PpgApp());
    await tester.tap(find.text('Live'));
    await tester.pump();
    expect(find.text('Waiting for live data…'), findsOneWidget);

    repo
        .connect(FakePpgDevice.defaultDeviceId)
        .then((_) => repo.startStreaming());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final first = tester
        .widget<LiveWaveform>(find.byType(LiveWaveform))
        .samples;
    await tester.pump(const Duration(milliseconds: 500));
    final second = tester
        .widget<LiveWaveform>(find.byType(LiveWaveform))
        .samples;
    expect(second, isNot(equals(first)));
    expect(second.length, greaterThan(first.length));

    // Stop the simulated device's timers inside the fake-time zone.
    sl<FakePpgDevice>().dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
