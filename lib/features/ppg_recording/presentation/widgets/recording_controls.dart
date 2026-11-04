import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../device_connection/domain/device_repository.dart';
import '../bloc/ppg_recording_bloc.dart';

/// Record / Stop button with persistence counters.
class RecordingControls extends StatelessWidget {
  /// Creates the controls.
  const RecordingControls({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<PpgRecordingBloc, PpgRecordingState>(
    listenWhen: (a, b) => b is RecordingIdle && b.failure != null && a != b,
    listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Recording error: ${(state as RecordingIdle).failure}'),
      ),
    ),
    builder: (context, state) => switch (state) {
      RecordingIdle() => FilledButton.icon(
        key: const Key('record-button'),
        icon: const Icon(Icons.fiber_manual_record),
        label: const Text('Record'),
        onPressed: () {
          final id = context.read<DeviceRepository>().connectedDeviceId;
          if (id == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Connect a device first')),
            );
            return;
          }
          context.read<PpgRecordingBloc>().add(RecordingStarted(id));
        },
      ),
      RecordingActive(:final savedPackets, :final batchesWritten) => Row(
        children: [
          FilledButton.tonalIcon(
            key: const Key('stop-button'),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            onPressed: () =>
                context.read<PpgRecordingBloc>().add(const RecordingStopped()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Saved $savedPackets packets in $batchesWritten batches',
            ),
          ),
        ],
      ),
    },
  );
}
