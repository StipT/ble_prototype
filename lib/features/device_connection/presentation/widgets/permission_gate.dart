import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/permission_cubit.dart';

/// Explains why BLE is blocked and offers the one action that can fix it:
/// show the dialog again, open Settings, or turn Bluetooth on.
///
/// Renders nothing once [PermissionGranted]; [child] is shown instead.
class PermissionGate extends StatelessWidget {
  /// [child] is the BLE UI shown when everything is granted.
  const PermissionGate({required this.child, super.key});

  /// Content shown when BLE is usable.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PermissionCubit, PermissionState>(
        builder: (context, state) {
          final cubit = context.read<PermissionCubit>();
          return switch (state) {
            PermissionGranted() => child,
            PermissionChecking() => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            PermissionDenied() => _Blocked(
              icon: Icons.bluetooth_disabled,
              message:
                  'Bluetooth permission is needed to find and connect to '
                  'your PPG sensor.',
              actionLabel: 'Grant permission',
              actionKey: const Key('grant-permission-button'),
              onAction: cubit.request,
            ),
            PermissionPermanentlyDenied() => _Blocked(
              icon: Icons.block,
              message:
                  'Bluetooth permission was denied permanently. Enable '
                  '"Nearby devices" / Bluetooth for this app in Settings.',
              actionLabel: 'Open settings',
              actionKey: const Key('open-settings-button'),
              onAction: cubit.openSettings,
            ),
            PermissionBluetoothOff(:final unsupported) => _Blocked(
              icon: Icons.bluetooth_disabled,
              message: unsupported
                  ? 'This device does not support Bluetooth Low Energy.'
                  : 'Bluetooth is off. Turn it on in quick settings / '
                        'Control Center.',
              actionLabel: 'Check again',
              actionKey: const Key('recheck-permission-button'),
              onAction: cubit.check,
            ),
          };
        },
      );
}

class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}
