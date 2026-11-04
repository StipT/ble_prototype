import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/cloud_sync_bloc.dart';

/// Cloud-sync status card: chunk counts per state and a "Sync now" button.
class CloudSyncPanel extends StatelessWidget {
  /// Creates the panel.
  const CloudSyncPanel({super.key});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: BlocBuilder<CloudSyncBloc, CloudSyncState>(
        builder: (context, s) {
          final syncing = s.status == CloudSyncStatus.syncing;
          final c = s.counts;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(s.online ? Icons.cloud_outlined : Icons.cloud_off),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_title(s), key: const Key('cloud-sync-status')),
                  ),
                  TextButton.icon(
                    key: const Key('cloud-sync-button'),
                    onPressed: syncing
                        ? null
                        : () => context.read<CloudSyncBloc>().add(
                            const CloudSyncRequested(),
                          ),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Sync now'),
                  ),
                ],
              ),
              if (syncing) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 4),
              Text(
                'Chunks: ${c.pending} pending · ${c.uploading} uploading · '
                '${c.synced} synced · ${c.failed} failed'
                '${c.pruned > 0 ? ' · ${c.pruned} pruned' : ''}'
                '${s.failure != null ? '\n${s.failure!.message}' : ''}',
                key: const Key('cloud-sync-counts'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    ),
  );

  static String _title(CloudSyncState s) => switch (s.status) {
    CloudSyncStatus.idle => 'Cloud sync: not run yet',
    CloudSyncStatus.syncing => 'Uploading (${s.trigger?.name})…',
    CloudSyncStatus.done => _doneTitle(s),
    CloudSyncStatus.offline => 'Offline — uploads resume when online',
    CloudSyncStatus.failed => 'Cloud sync failed',
  };

  static String _doneTitle(CloudSyncState s) {
    final r = s.lastReport;
    if (r == null) return 'Cloud sync done';
    if (r.failed > 0) return 'Uploaded ${r.uploaded}, ${r.failed} failed';
    if (r.retryScheduled > 0) {
      return 'Uploaded ${r.uploaded}, ${r.retryScheduled} will retry';
    }
    return 'Cloud up to date (uploaded ${r.uploaded})';
  }
}
