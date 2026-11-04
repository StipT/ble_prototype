import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:ble_prototype/features/ppg_recording/data/drift_recording_repository.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/cubit/sessions_cubit.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/pages/sessions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/packets.dart';
import '../../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DriftRecordingRepository repo;

  setUp(() {
    db = testDatabase();
    repo = DriftRecordingRepository(db);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => SessionsCubit(repo),
            child: const SessionsPage(),
          ),
        ),
      ),
    );
    // Drift runs queries off the fake clock: let them complete for real.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  Future<void> tearDownPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  testWidgets('shows the empty state when nothing is stored', (tester) async {
    await pumpPage(tester);
    expect(find.text('No sessions recorded yet'), findsOneWidget);
    await tearDownPage(tester);
  });

  testWidgets('lists sessions stored in the database', (tester) async {
    await tester.runAsync(() async {
      final a = (await repo.startSession(
        deviceId: 'a',
        startedAt: DateTime(2026, 1, 1, 10),
      )).valueOrNull!;
      await repo.savePackets(a.id, packets(0, 9));
      await repo.savePackets(
        a.id,
        packets(12, 14, kind: PpgPacketKind.history),
      );
      await repo.endSession(a.id, DateTime(2026, 1, 1, 11));
      await repo.startSession(
        deviceId: 'b',
        startedAt: DateTime(2026, 1, 1, 12),
      );
    });

    await pumpPage(tester);

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.textContaining('2026-01-01 12:00:00'), findsOneWidget);
    expect(
      find.textContaining('13 packets (3 from history) · 2 missing'),
      findsOneWidget,
    );
    expect(find.textContaining('0/1 synced · 1 pending'), findsOneWidget);
    // Newest (still recording) first.
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.leading! as Icon).icon, Icons.fiber_manual_record);
    await tearDownPage(tester);
  });
}
