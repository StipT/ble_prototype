import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart' show Storage;

import '../core/di/injection.dart';
import '../core/stream/stream_extensions.dart';
import '../core/theme/app_theme.dart';
import '../features/cloud_sync/domain/cloud_sync_repository.dart';
import '../features/cloud_sync/domain/connectivity_monitor.dart';
import '../features/cloud_sync/presentation/bloc/cloud_sync_bloc.dart';
import '../features/cloud_sync/presentation/widgets/cloud_sync_panel.dart';
import '../features/device_connection/data/fake/fake_ppg_device.dart';
import '../features/device_connection/domain/device_repository.dart';
import '../features/device_connection/domain/permission_service.dart';
import '../features/device_connection/presentation/bloc/device_connection_bloc.dart';
import '../features/device_connection/presentation/cubit/permission_cubit.dart';
import '../features/device_connection/presentation/pages/device_page.dart';
import '../features/device_sync/presentation/bloc/device_sync_bloc.dart';
import '../features/pairing_nfc/domain/nfc_reader.dart';
import '../features/pairing_nfc/presentation/bloc/pairing_bloc.dart';
import '../features/ppg_recording/domain/recording_repository.dart';
import '../features/ppg_recording/presentation/bloc/live_waveform_bloc.dart';
import '../features/ppg_recording/presentation/bloc/ppg_recording_bloc.dart';
import '../features/ppg_recording/presentation/cubit/sessions_cubit.dart';
import '../features/ppg_recording/presentation/pages/live_page.dart';
import '../features/ppg_recording/presentation/pages/sessions_page.dart';

/// Root widget: provides repositories and app-wide blocs, then the shell.
class PpgApp extends StatelessWidget {
  /// Creates the app.
  const PpgApp({super.key});

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<DeviceRepository>.value(value: sl<DeviceRepository>()),
      RepositoryProvider<RecordingRepository>.value(
        value: sl<RecordingRepository>(),
      ),
      RepositoryProvider<PermissionService>.value(
        value: sl<PermissionService>(),
      ),
      RepositoryProvider<CloudSyncRepository>.value(
        value: sl<CloudSyncRepository>(),
      ),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => PermissionCubit(
            permissions: context.read<PermissionService>(),
            adapterStatus: context.read<DeviceRepository>().adapterStatus,
          )..check(),
        ),
        BlocProvider(
          create: (context) =>
              DeviceConnectionBloc(device: context.read<DeviceRepository>()),
        ),
        BlocProvider(
          // Eager: the NFC availability check runs at start-up, so the
          // Device tab never flashes "Checking NFC…".
          lazy: false,
          create: (context) {
            final connection = context.read<DeviceConnectionBloc>();
            return PairingBloc(
              reader: sl<NfcReader>(),
              storage: sl<Storage>(),
              connectDevice: (id) => connection.add(DeviceConnectRequested(id)),
            )..add(const PairingAvailabilityChecked());
          },
        ),
        BlocProvider(
          create: (context) =>
              LiveWaveformBloc(repository: context.read<DeviceRepository>())
                ..add(const LiveWaveformSubscriptionRequested()),
        ),
        BlocProvider(
          create: (context) => PpgRecordingBloc(
            device: context.read<DeviceRepository>(),
            recording: context.read<RecordingRepository>(),
          ),
        ),
        BlocProvider(
          create: (context) =>
              SessionsCubit(context.read<RecordingRepository>()),
        ),
        BlocProvider(
          // Eager: it must hear every (re)connect, not only once the Live
          // tab reads it.
          lazy: false,
          create: (context) {
            final connection = context.read<DeviceConnectionBloc>();
            return DeviceSyncBloc(
              device: context.read<DeviceRepository>(),
              recording: context.read<RecordingRepository>(),
              // "Ready" = the connection bloc finished connect → MTU →
              // clock sync → start streaming, not merely "link up".
              linkReady: connection.stream
                  .startWith(() => connection.state)
                  .map((s) => s.isConnected)
                  .distinct(),
            );
          },
        ),
        BlocProvider(
          // Eager: uploads run in the background whatever tab is open.
          lazy: false,
          create: (context) => CloudSyncBloc(
            repository: context.read<CloudSyncRepository>(),
            connectivity: sl<ConnectivityMonitor>(),
          )..add(const CloudSyncStarted()),
        ),
      ],
      // Session end makes the last, partial chunk eligible for upload.
      child: BlocListener<PpgRecordingBloc, PpgRecordingState>(
        listenWhen: (previous, current) =>
            previous is RecordingActive && current is RecordingIdle,
        listener: (context, _) => context.read<CloudSyncBloc>().add(
          const CloudSyncRequested(trigger: CloudSyncTrigger.sessionEnded),
        ),
        child: MaterialApp(
          title: 'PPG BLE Sync',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: HomeShell(
            fakeDevice: sl.isRegistered<FakePpgDevice>()
                ? sl<FakePpgDevice>()
                : null,
          ),
        ),
      ),
    ),
  );
}

/// Top-level navigation.
class HomeShell extends StatefulWidget {
  /// [fakeDevice] enables the debug fault panel on the Device tab.
  const HomeShell({this.fakeDevice, super.key});

  /// Simulator in use, `null` with real hardware.
  final FakePpgDevice? fakeDevice;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Device', 'Live', 'Sessions'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('PPG BLE Sync · ${_titles[_tab]}')),
    body: IndexedStack(
      index: _tab,
      children: [
        DevicePage(fakeDevice: widget.fakeDevice),
        const LivePage(),
        const SessionsPage(header: CloudSyncPanel()),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Device'),
        NavigationDestination(icon: Icon(Icons.monitor_heart), label: 'Live'),
        NavigationDestination(icon: Icon(Icons.storage), label: 'Sessions'),
      ],
    ),
  );
}
