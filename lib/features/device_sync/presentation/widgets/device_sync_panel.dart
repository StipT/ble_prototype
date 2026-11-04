import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/device_sync_bloc.dart';

/// History-sync status card with a manual "Sync history" button.
///
/// History sync normally runs by itself (after every reconnect and after a
/// gap in the live stream); the button is there to demonstrate and debug
/// the resume-by-sequence logic on demand.
class DeviceSyncPanel extends StatelessWidget {
  /// Creates the panel.
  const DeviceSyncPanel({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: BlocBuilder<DeviceSyncBloc, DeviceSyncState>(
        builder: (context, s) {
          final syncing = s.status == DeviceSyncStatus.syncing;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title(s),
                      key: const Key('device-sync-status'),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('device-sync-button'),
                    onPressed: syncing
                        ? null
                        : () => context.read<DeviceSyncBloc>().add(
                            const DeviceSyncRequested(),
                          ),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync history'),
                  ),
                ],
              ),
              if (syncing) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: s.progress),
              ],
              if (s.packetsRequested > 0 || s.failure != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Requested ${s.packetsRequested} · received '
                  '${s.packetsReceived} · new ${s.packetsSaved} · ranges '
                  '${s.rangesDone}/${s.rangesTotal}'
                  '${s.failure != null ? '\n${s.failure}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    ),
  );

  static String _title(DeviceSyncState s) => switch (s.status) {
    DeviceSyncStatus.idle => 'History sync: not run yet',
    DeviceSyncStatus.syncing => 'Downloading history (${s.trigger?.name})…',
    DeviceSyncStatus.upToDate => 'History up to date',
    DeviceSyncStatus.noSession => 'History sync: not recording',
    DeviceSyncStatus.failed => 'History sync interrupted — resumes later',
  };
}
