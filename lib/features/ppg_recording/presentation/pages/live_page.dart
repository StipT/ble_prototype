import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../device_sync/presentation/widgets/device_sync_panel.dart';
import '../bloc/live_waveform_bloc.dart';
import '../widgets/recording_controls.dart';
import '../widgets/waveform_painter.dart';

/// Live PPG waveform, recording controls and history-sync status.
class LivePage extends StatelessWidget {
  /// Creates the page.
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final window = context.read<LiveWaveformBloc>().window;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    BlocSelector<
                      LiveWaveformBloc,
                      LiveWaveformState,
                      List<int>
                    >(
                      selector: (s) => s.samples,
                      builder: (context, samples) => samples.isEmpty
                          ? const Center(child: Text('Waiting for live data…'))
                          : LiveWaveform(samples: samples, capacity: window),
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          BlocBuilder<LiveWaveformBloc, LiveWaveformState>(
            buildWhen: (a, b) =>
                a.packetCount != b.packetCount || a.gapPackets != b.gapPackets,
            builder: (context, s) => Text(
              'Packets: ${s.packetCount}   last #${s.lastSequence ?? '-'}   '
              'gaps: ${s.gapPackets}',
              key: const Key('live-stats'),
            ),
          ),
          const SizedBox(height: 16),
          const RecordingControls(),
          const SizedBox(height: 16),
          const DeviceSyncPanel(),
        ],
      ),
    );
  }
}
