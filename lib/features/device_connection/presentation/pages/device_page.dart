import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../pairing_nfc/presentation/bloc/pairing_bloc.dart';
import '../../../pairing_nfc/presentation/widgets/nfc_pairing_card.dart';
import '../../data/fake/fake_ppg_device.dart';
import '../cubit/permission_cubit.dart';
import '../widgets/connection_panel.dart';
import '../widgets/debug_fault_panel.dart';
import '../widgets/permission_gate.dart';

/// Permissions → NFC tap-to-pair / scan → connect → battery/status, plus
/// the debug fault panel when running against the simulator.
class DevicePage extends StatefulWidget {
  /// [fakeDevice] enables the [DebugFaultPanel]; pass `null` with real
  /// hardware.
  const DevicePage({this.fakeDevice, super.key});

  /// Simulator to expose in the debug panel, if any.
  final FakePpgDevice? fakeDevice;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  // Neither OS notifies the app when the user changes a permission in
  // Settings, so re-check every time the app comes back to the foreground.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        context.read<PermissionCubit>().check();
        // NFC may have been switched on/off in Settings meanwhile.
        context.read<PairingBloc>().add(const PairingAvailabilityChecked());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const PermissionGate(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [NfcPairingCard(), SizedBox(height: 8), ConnectionPanel()],
        ),
      ),
      if (widget.fakeDevice case final fake?) ...[
        const SizedBox(height: 16),
        DebugFaultPanel(device: fake),
      ],
    ],
  );
}
