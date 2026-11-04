import 'dart:async';

import 'package:ble_prototype/features/device_connection/domain/device_repository.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:ble_prototype/features/ppg_recording/presentation/bloc/live_waveform_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

PpgPacket _p(int seq, List<int> samples) =>
    PpgPacket(sequence: seq, timestamp: DateTime(2026), samples: samples);

void main() {
  late _MockDeviceRepository repo;
  late StreamController<PpgPacket> live;

  setUp(() {
    repo = _MockDeviceRepository();
    live = StreamController<PpgPacket>.broadcast();
    when(() => repo.livePackets).thenAnswer((_) => live.stream);
  });

  tearDown(() => live.close());

  blocTest<LiveWaveformBloc, LiveWaveformState>(
    'appends samples, keeps a bounded window and counts gaps',
    build: () => LiveWaveformBloc(repository: repo, window: 4),
    act: (bloc) async {
      bloc.add(const LiveWaveformSubscriptionRequested());
      await Future<void>.delayed(Duration.zero);
      live
        ..add(_p(1, [1, 2]))
        ..add(_p(2, [3, 4]))
        ..add(_p(5, [5, 6])); // 3 and 4 dropped
    },
    expect: () => const [
      LiveWaveformState(samples: [1, 2], lastSequence: 1, packetCount: 1),
      LiveWaveformState(samples: [1, 2, 3, 4], lastSequence: 2, packetCount: 2),
      LiveWaveformState(
        samples: [3, 4, 5, 6],
        lastSequence: 5,
        packetCount: 3,
        gapPackets: 2,
      ),
    ],
  );

  blocTest<LiveWaveformBloc, LiveWaveformState>(
    'restartable: re-subscribing does not duplicate packets',
    build: () => LiveWaveformBloc(repository: repo, window: 10),
    act: (bloc) async {
      bloc
        ..add(const LiveWaveformSubscriptionRequested())
        ..add(const LiveWaveformSubscriptionRequested());
      await Future<void>.delayed(Duration.zero);
      live.add(_p(1, [7]));
    },
    expect: () => const [
      LiveWaveformState(samples: [7], lastSequence: 1, packetCount: 1),
    ],
  );
}
