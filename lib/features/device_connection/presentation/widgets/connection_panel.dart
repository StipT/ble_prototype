import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/device_status.dart';
import '../bloc/device_connection_bloc.dart';

/// Scan button, scan results, link phase, battery/status and disconnect.
class ConnectionPanel extends StatelessWidget {
  /// Creates the panel.
  const ConnectionPanel({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DeviceConnectionBloc, DeviceConnectionState>(
    builder: (context, state) {
      final bloc = context.read<DeviceConnectionBloc>();
      final busy = state.phase != ConnectionPhase.idle;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: Icon(_phaseIcon(state.phase)),
              title: Text(
                _phaseLabel(state),
                key: const Key('connection-phase'),
              ),
              subtitle: state.deviceId == null ? null : Text(state.deviceId!),
              trailing: switch (state.phase) {
                ConnectionPhase.connected ||
                ConnectionPhase.reconnecting => OutlinedButton(
                  key: const Key('disconnect-button'),
                  onPressed: () => bloc.add(const DeviceDisconnectRequested()),
                  child: const Text('Disconnect'),
                ),
                _ => null,
              },
            ),
          ),
          if (state.failure case final failure?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                failure.message,
                key: const Key('connection-failure'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (state.status case final status? when state.isConnected)
            _StatusCard(status: status),
          if (!state.isConnected &&
              state.phase != ConnectionPhase.reconnecting) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('scan-button'),
              icon: state.phase == ConnectionPhase.scanning
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(
                state.phase == ConnectionPhase.scanning ? 'Scanning…' : 'Scan',
              ),
              onPressed: busy
                  ? null
                  : () => bloc.add(const DeviceScanRequested()),
            ),
            for (final d in state.devices)
              ListTile(
                key: Key('device-${d.id}'),
                leading: const Icon(Icons.sensors),
                title: Text(d.name.isEmpty ? '(no name)' : d.name),
                subtitle: Text('${d.id} · ${d.rssi} dBm'),
                trailing: TextButton(
                  key: Key('connect-${d.id}'),
                  onPressed: busy
                      ? null
                      : () => bloc.add(DeviceConnectRequested(d.id)),
                  child: const Text('Connect'),
                ),
              ),
          ],
        ],
      );
    },
  );

  static IconData _phaseIcon(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => Icons.bluetooth_connected,
    ConnectionPhase.scanning => Icons.bluetooth_searching,
    ConnectionPhase.reconnecting ||
    ConnectionPhase.connecting => Icons.bluetooth_searching,
    _ => Icons.bluetooth,
  };

  static String _phaseLabel(DeviceConnectionState s) => switch (s.phase) {
    ConnectionPhase.idle => 'Not connected',
    ConnectionPhase.scanning => 'Scanning…',
    ConnectionPhase.connecting => 'Connecting…',
    ConnectionPhase.connected => 'Connected',
    ConnectionPhase.disconnecting => 'Disconnecting…',
    ConnectionPhase.reconnecting => switch (s.nextRetryIn) {
      final d? =>
        'Reconnecting (attempt ${s.reconnectAttempt}) in '
            '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s',
      null => 'Reconnecting (attempt ${s.reconnectAttempt})…',
    },
  };
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.isCharging
                    ? Icons.battery_charging_full
                    : Icons.battery_std,
              ),
              const SizedBox(width: 8),
              Text(
                'Battery: ${status.batteryPercent}%'
                '${status.isCharging ? ' (charging)' : ''}',
                key: const Key('battery-text'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(status.isStreaming ? 'Streaming live data' : 'Not streaming'),
          Text(
            status.hasData
                ? 'Device backlog: #${status.oldestSequence}'
                      '–#${status.latestSequence}'
                : 'Device backlog: empty',
          ),
        ],
      ),
    ),
  );
}
