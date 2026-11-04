import 'package:ble_prototype/features/device_sync/presentation/bloc/device_sync_bloc.dart';
import 'package:ble_prototype/features/device_sync/presentation/widgets/device_sync_panel.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSyncBloc extends MockBloc<DeviceSyncEvent, DeviceSyncState>
    implements DeviceSyncBloc {}

void main() {
  late _MockSyncBloc bloc;

  setUp(() => bloc = _MockSyncBloc());

  Widget app() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<DeviceSyncBloc>.value(
        value: bloc,
        child: const DeviceSyncPanel(),
      ),
    ),
  );

  testWidgets('"Sync history" requests a manual sync', (tester) async {
    when(
      () => bloc.state,
    ).thenReturn(const DeviceSyncState(status: DeviceSyncStatus.upToDate));
    await tester.pumpWidget(app());
    expect(find.text('History up to date'), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-sync-button')));
    verify(() => bloc.add(const DeviceSyncRequested())).called(1);
  });

  testWidgets('shows progress and disables the button while syncing', (
    tester,
  ) async {
    when(() => bloc.state).thenReturn(
      const DeviceSyncState(
        status: DeviceSyncStatus.syncing,
        trigger: DeviceSyncTrigger.connected,
        rangesTotal: 2,
        packetsRequested: 200,
        packetsReceived: 50,
        packetsSaved: 50,
      ),
    );
    await tester.pumpWidget(app());
    expect(find.text('Downloading history (connected)…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.25);
    final button = tester.widget<TextButton>(
      find.byKey(const Key('device-sync-button')),
    );
    expect(button.onPressed, isNull);
  });
}
