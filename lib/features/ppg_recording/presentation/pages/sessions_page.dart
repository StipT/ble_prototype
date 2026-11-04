import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../device_connection/data/protocol/ppg_packet_codec.dart';
import '../../domain/entities/session.dart';
import '../cubit/sessions_cubit.dart';

/// Sessions read from the local database.
class SessionsPage extends StatelessWidget {
  /// Creates the page. [actions] are shown above the list (e.g. Sync now).
  const SessionsPage({super.key, this.header});

  /// Optional widget above the list.
  final Widget? header;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ?header,
      Expanded(
        child: BlocBuilder<SessionsCubit, SessionsState>(
          builder: (context, state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.sessions.isEmpty) {
              return const Center(child: Text('No sessions recorded yet'));
            }
            return ListView.separated(
              itemCount: state.sessions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _SessionTile(state.sessions[i]),
            );
          },
        ),
      ),
    ],
  );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile(this.summary);

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary.session;
    final seconds = summary
        .durationSeconds(PpgPacketCodec.samplesPerPacket)
        .toStringAsFixed(1);
    final started = s.startedAt.toLocal().toString().substring(0, 19);
    return ListTile(
      leading: Icon(
        s.isActive ? Icons.fiber_manual_record : Icons.check_circle_outline,
        color: s.isActive ? Colors.red : null,
      ),
      title: Text('$started  ·  ${seconds}s'),
      subtitle: Text(
        '${summary.packetCount} packets'
        '${summary.historyPacketCount > 0 ? ' (${summary.historyPacketCount} from history)' : ''}'
        '${summary.missingPackets > 0 ? ' · ${summary.missingPackets} missing' : ''}\n'
        'chunks: ${summary.syncedChunks}/${summary.chunkCount} synced'
        '${summary.pendingChunks > 0 ? ' · ${summary.pendingChunks} pending' : ''}'
        '${summary.uploadingChunks > 0 ? ' · ${summary.uploadingChunks} uploading' : ''}'
        '${summary.failedChunks > 0 ? ' · ${summary.failedChunks} failed' : ''}',
      ),
      isThreeLine: true,
    );
  }
}
