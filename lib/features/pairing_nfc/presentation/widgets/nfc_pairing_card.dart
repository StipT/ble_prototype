import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../device_connection/presentation/bloc/device_connection_bloc.dart';
import '../../domain/nfc_reader.dart';
import '../bloc/pairing_bloc.dart';

/// "Tap to pair" card on the Device tab, plus the remembered device with
/// Reconnect / Forget.
///
/// Pairing actions are only enabled while the BLE link is idle (like the
/// Scan button): the connection flow handles one target at a time. When NFC
/// is off or unsupported the card says so and points to Scan below.
class NfcPairingCard extends StatelessWidget {
  /// Creates the card.
  const NfcPairingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final linkIdle = context.select(
      (DeviceConnectionBloc b) => b.state.phase == ConnectionPhase.idle,
    );
    return BlocBuilder<PairingBloc, PairingState>(
      builder: (context, state) {
        final bloc = context.read<PairingBloc>();
        final waiting = state.phase == PairingPhase.waitingForTag;
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.nfc),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap to pair',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _hint(state),
                  key: const Key('nfc-hint'),
                  style: theme.textTheme.bodySmall,
                ),
                if (state.failure case final failure?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      failure.message,
                      key: const Key('nfc-failure'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                if (waiting)
                  OutlinedButton.icon(
                    key: const Key('nfc-cancel-button'),
                    icon: const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Waiting for tag… Cancel'),
                    onPressed: () => bloc.add(const PairingTapCancelled()),
                  )
                else if (state.canUseNfc)
                  FilledButton.tonalIcon(
                    key: const Key('nfc-pair-button'),
                    icon: const Icon(Icons.contactless),
                    label: const Text('Tap to pair'),
                    onPressed: linkIdle
                        ? () => bloc.add(const PairingTapRequested())
                        : null,
                  ),
                if (state.lastPaired case final device?) ...[
                  const Divider(),
                  ListTile(
                    key: const Key('last-paired'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text('Last paired: ${device.label}'),
                    subtitle: Text(device.deviceId),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const Key('forget-button'),
                        onPressed: waiting
                            ? null
                            : () => bloc.add(const PairingForgotten()),
                        child: const Text('Forget'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('reconnect-button'),
                        onPressed: linkIdle && !waiting
                            ? () => bloc.add(const PairingReconnectRequested())
                            : null,
                        child: const Text('Reconnect'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _hint(PairingState state) => switch (state.nfcStatus) {
    _ when state.phase == PairingPhase.waitingForTag =>
      "Hold the phone against the sensor's NFC tag",
    NfcStatus.available =>
      'Touch the sensor with your phone to connect without scanning.',
    NfcStatus.disabled =>
      'NFC is turned off. Enable it in system settings, or use Scan below.',
    NfcStatus.unsupported =>
      'NFC is not available on this device. Use Scan below.',
    null => 'Checking NFC…',
  };
}
