import 'dart:async';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/device_connection/domain/device_repository.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ble_types.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/device_status.dart';
import 'package:ble_prototype/features/device_connection/domain/reconnect_policy.dart';
import 'package:ble_prototype/features/device_connection/presentation/bloc/device_connection_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

const _id = 'AA:BB:CC:DD:EE:FF';
const _device = DiscoveredPpgDevice(id: _id, name: 'PPG', rssi: -50);
const _status = DeviceStatus(
  batteryPercent: 87,
  isStreaming: true,
  isCharging: false,
  hasData: true,
  oldestSequence: 0,
  latestSequence: 42,
);

void main() {
  late _MockDeviceRepository repo;
  late StreamController<DeviceLinkState> link;
  late StreamController<DeviceStatus> statuses;
  late DeviceLinkState currentLink;
  late List<Result<void, Failure>> connectResults;
  late List<Duration> delays;

  setUpAll(() => registerFallbackValue(Duration.zero));

  setUp(() {
    repo = _MockDeviceRepository();
    link = StreamController<DeviceLinkState>.broadcast();
    statuses = StreamController<DeviceStatus>.broadcast();
    currentLink = DeviceLinkState.disconnected;
    connectResults = [];
    delays = [];

    when(() => repo.linkState).thenAnswer((_) => link.stream);
    when(() => repo.statusUpdates).thenAnswer((_) => statuses.stream);
    when(() => repo.currentLinkState).thenAnswer((_) => currentLink);
    when(() => repo.connect(any())).thenAnswer((_) async {
      final result = connectResults.isEmpty
          ? okVoid
          : connectResults.removeAt(0);
      if (result.isOk) currentLink = DeviceLinkState.connected;
      return result;
    });
    when(() => repo.startStreaming()).thenAnswer((_) async => okVoid);
    when(() => repo.readStatus()).thenAnswer((_) async => const Ok(_status));
    when(() => repo.disconnect()).thenAnswer((_) async {
      currentLink = DeviceLinkState.disconnected;
      link.add(DeviceLinkState.disconnected);
    });
  });

  tearDown(() async {
    await link.close();
    await statuses.close();
  });

  DeviceConnectionBloc build({
    ReconnectPolicy policy = const ReconnectPolicy(
      initialDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 4),
    ),
    Sleeper? sleeper,
  }) => DeviceConnectionBloc(
    device: repo,
    policy: policy,
    sleeper: sleeper ?? (d) async => delays.add(d),
  );

  /// Simulates an unexpected link loss reported by the radio.
  Future<void> dropLink() async {
    currentLink = DeviceLinkState.disconnected;
    link.add(DeviceLinkState.disconnected);
    await pumpEventQueue();
  }

  const connecting = DeviceConnectionState(
    phase: ConnectionPhase.connecting,
    deviceId: _id,
  );
  const connected = DeviceConnectionState(
    phase: ConnectionPhase.connected,
    deviceId: _id,
    status: _status,
  );
  const reconnecting = DeviceConnectionState(
    phase: ConnectionPhase.reconnecting,
    deviceId: _id,
    failure: ConnectionLost(),
  );

  group('scan', () {
    void stubScan(Result<List<DiscoveredPpgDevice>, Failure> r) => when(
      () => repo.scan(timeout: any(named: 'timeout')),
    ).thenAnswer((_) async => r);

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'lists the devices found',
      setUp: () => stubScan(const Ok([_device])),
      build: build,
      act: (b) => b.add(const DeviceScanRequested()),
      expect: () => const [
        DeviceConnectionState(phase: ConnectionPhase.scanning),
        DeviceConnectionState(devices: [_device]),
      ],
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'an empty scan is reported as DeviceNotFound',
      setUp: () => stubScan(const Ok([])),
      build: build,
      act: (b) => b.add(const DeviceScanRequested()),
      skip: 1,
      expect: () => [
        isA<DeviceConnectionState>()
            .having((s) => s.phase, 'phase', ConnectionPhase.idle)
            .having((s) => s.failure, 'failure', isA<DeviceNotFound>()),
      ],
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'BluetoothOff / BlePermissionDenied from the scan surface as failures',
      setUp: () => stubScan(const Err(BlePermissionDenied())),
      build: build,
      act: (b) async {
        b.add(const DeviceScanRequested());
        await pumpEventQueue();
        stubScan(const Err(BluetoothOff()));
        b.add(const DeviceScanRequested());
      },
      expect: () => const [
        DeviceConnectionState(phase: ConnectionPhase.scanning),
        DeviceConnectionState(failure: BlePermissionDenied()),
        DeviceConnectionState(phase: ConnectionPhase.scanning),
        DeviceConnectionState(failure: BluetoothOff()),
      ],
    );
  });

  group('connect', () {
    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'connects, starts streaming and shows battery/status',
      build: build,
      act: (b) => b.add(const DeviceConnectRequested(_id)),
      expect: () => const [connecting, connected],
      verify: (_) {
        verifyInOrder([
          () => repo.connect(_id),
          () => repo.startStreaming(),
          () => repo.readStatus(),
        ]);
      },
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'status notifications update the battery while connected',
      build: build,
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
        statuses.add(
          const DeviceStatus(
            batteryPercent: 50,
            isStreaming: true,
            isCharging: true,
            hasData: true,
            oldestSequence: 0,
            latestSequence: 100,
          ),
        );
      },
      skip: 2,
      expect: () => [
        isA<DeviceConnectionState>()
            .having((s) => s.status?.batteryPercent, 'battery', 50)
            .having((s) => s.status?.isCharging, 'charging', isTrue),
      ],
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'a failed first connect is reported and not retried',
      setUp: () => connectResults = [const Err(DeviceNotFound())],
      build: build,
      act: (b) => b.add(const DeviceConnectRequested(_id)),
      expect: () => const [
        connecting,
        DeviceConnectionState(deviceId: _id, failure: DeviceNotFound()),
      ],
      verify: (_) {
        expect(delays, isEmpty);
        verifyNever(() => repo.startStreaming());
      },
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'a thrown platform error is mapped to a Failure',
      setUp: () => when(
        () => repo.connect(any()),
      ).thenThrow(Exception('GATT error 133')),
      build: build,
      act: (b) => b.add(const DeviceConnectRequested(_id)),
      skip: 1,
      expect: () => [
        isA<DeviceConnectionState>()
            .having((s) => s.phase, 'phase', ConnectionPhase.idle)
            .having((s) => s.failure, 'failure', isA<ConnectionLost>()),
      ],
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'a user disconnect does not trigger a reconnect',
      build: build,
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
        b.add(const DeviceDisconnectRequested());
        await pumpEventQueue();
      },
      skip: 2,
      expect: () => const [
        DeviceConnectionState(
          phase: ConnectionPhase.disconnecting,
          deviceId: _id,
          status: _status,
        ),
        DeviceConnectionState(deviceId: _id),
      ],
      verify: (_) {
        expect(delays, isEmpty);
        verify(() => repo.connect(_id)).called(1);
      },
    );
  });

  group('auto-reconnect', () {
    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'retries with exponential backoff and restarts streaming',
      setUp: () => connectResults = [
        okVoid,
        const Err(DeviceNotFound()),
        const Err(DeviceNotFound()),
        okVoid,
      ],
      build: build,
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
        await dropLink();
      },
      expect: () => [
        connecting,
        connected,
        reconnecting,
        reconnecting.copyWith(
          reconnectAttempt: 1,
          nextRetryIn: () => const Duration(seconds: 1),
        ),
        reconnecting.copyWith(reconnectAttempt: 1),
        reconnecting.copyWith(
          reconnectAttempt: 1,
          failure: () => const DeviceNotFound(),
        ),
        reconnecting.copyWith(
          reconnectAttempt: 2,
          failure: () => const DeviceNotFound(),
          nextRetryIn: () => const Duration(seconds: 2),
        ),
        // Attempt 2 then fails with the same failure: no extra emission.
        reconnecting.copyWith(
          reconnectAttempt: 2,
          failure: () => const DeviceNotFound(),
        ),
        reconnecting.copyWith(
          reconnectAttempt: 3,
          failure: () => const DeviceNotFound(),
          nextRetryIn: () => const Duration(seconds: 4),
        ),
        reconnecting.copyWith(
          reconnectAttempt: 3,
          failure: () => const DeviceNotFound(),
        ),
        connected,
      ],
      verify: (_) {
        expect(delays, const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ]);
        // startStreaming is re-sent after every successful (re)connect.
        verify(() => repo.startStreaming()).called(2);
      },
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'the delay is capped at maxDelay',
      setUp: () => connectResults = [
        okVoid,
        for (var i = 0; i < 6; i++) const Err(ConnectionLost()),
        okVoid,
      ],
      build: build,
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
        await dropLink();
      },
      verify: (b) {
        expect(delays.map((d) => d.inSeconds), [1, 2, 4, 4, 4, 4, 4]);
        expect(b.state, connected);
      },
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'gives up after maxAttempts',
      setUp: () => connectResults = [
        okVoid,
        const Err(BluetoothOff()),
        const Err(BluetoothOff()),
      ],
      build: () => build(
        policy: const ReconnectPolicy(
          initialDelay: Duration(milliseconds: 500),
          maxAttempts: 2,
        ),
      ),
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
        await dropLink();
      },
      verify: (b) {
        expect(delays, const [
          Duration(milliseconds: 500),
          Duration(seconds: 1),
        ]);
        expect(b.state.phase, ConnectionPhase.idle);
        expect(b.state.failure, isA<ConnectionLost>());
        verify(() => repo.connect(_id)).called(3);
      },
    );

    final never = Completer<void>();
    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'Disconnect cancels a reconnect loop that is waiting',
      build: () => build(
        sleeper: (d) {
          delays.add(d);
          return never.future;
        },
      ),
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
        await dropLink();
        b.add(const DeviceDisconnectRequested());
        await pumpEventQueue();
      },
      verify: (b) {
        expect(delays, const [Duration(seconds: 1)]);
        expect(b.state.phase, ConnectionPhase.idle);
        expect(b.state.failure, isNull);
        verify(() => repo.connect(_id)).called(1);
      },
    );

    blocTest<DeviceConnectionBloc, DeviceConnectionState>(
      'a drop during the connect handshake is caught after connecting',
      setUp: () => when(() => repo.startStreaming()).thenAnswer((_) async {
        // Link is lost right after streaming starts, before the bloc
        // reaches "connected": the notification is ignored at that moment.
        if (connectResults.isEmpty && delays.isEmpty) {
          currentLink = DeviceLinkState.disconnected;
          link.add(DeviceLinkState.disconnected);
        }
        return okVoid;
      }),
      build: build,
      act: (b) async {
        b.add(const DeviceConnectRequested(_id));
        await pumpEventQueue();
      },
      verify: (b) {
        expect(delays, const [Duration(seconds: 1)]);
        expect(b.state, connected);
      },
    );
  });

  test('the default sleeper timer is cancelled on close', () async {
    final bloc = DeviceConnectionBloc(device: repo);
    bloc.add(const DeviceConnectRequested(_id));
    await pumpEventQueue();
    await dropLink();
    expect(bloc.state.nextRetryIn, const Duration(seconds: 1));
    await bloc.close();
    verify(() => repo.connect(_id)).called(1);
  });
}
