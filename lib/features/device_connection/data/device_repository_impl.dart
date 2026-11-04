import 'dart:async';

import 'package:clock/clock.dart';

import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/device_repository.dart';
import '../domain/entities/ble_types.dart';
import '../domain/entities/device_status.dart';
import '../domain/entities/ppg_packet.dart';
import 'adapters/ppg_device_adapter.dart';
import 'protocol/ppg_packet_codec.dart';

/// [DeviceRepository] built from a byte-level [PpgDeviceAdapter] and the
/// [PpgPacketCodec].
///
/// The adapter's notification streams are decoded exactly once and shared
/// (`asBroadcastStream`), so the waveform, recorder and history sync all see
/// the same frames without decoding them three times.
class DeviceRepositoryImpl implements DeviceRepository {
  /// [adapter] is the fake or real radio; [codec] the protocol definition.
  DeviceRepositoryImpl({
    required PpgDeviceAdapter adapter,
    PpgPacketCodec codec = const PpgPacketCodec(),
  }) : _adapter = adapter,
       _codec = codec;

  final PpgDeviceAdapter _adapter;
  final PpgPacketCodec _codec;
  final _protocolErrors = StreamController<ProtocolError>.broadcast();

  late final Stream<PpgFrame> _frames = _adapter.ppgNotifications
      .expand<PpgFrame>((raw) {
        switch (_codec.decodeFrame(raw)) {
          case Ok(:final value):
            return [value];
          case Err(:final failure):
            _protocolErrors.add(failure);
            return const [];
        }
      })
      .asBroadcastStream();

  @override
  Stream<BluetoothAdapterStatus> get adapterStatus => _adapter.adapterStatus;

  @override
  Stream<DeviceLinkState> get linkState => _adapter.linkState;

  @override
  DeviceLinkState get currentLinkState => _adapter.currentLinkState;

  @override
  String? get connectedDeviceId => _adapter.connectedDeviceId;

  @override
  Stream<ProtocolError> get protocolErrors => _protocolErrors.stream;

  @override
  Future<Result<List<DiscoveredPpgDevice>, Failure>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final found = <String, DiscoveredPpgDevice>{};
    try {
      await for (final d in _adapter.scan(timeout: timeout)) {
        found[d.id] = d;
      }
    } on Failure catch (f) {
      return Err(f);
    }
    final list = found.values.toList()..sort((a, b) => b.rssi - a.rssi);
    return Ok(list);
  }

  @override
  Future<Result<void, Failure>> connect(String deviceId) async {
    final connected = await _adapter.connect(deviceId);
    if (connected is Err) return connected;

    // 5 samples need 29 bytes > the default 20-byte payload: negotiate first.
    final mtu = await _adapter.requestMtu(PpgPacketCodec.preferredMtu);
    if (mtu case Err(:final failure)) return Err(failure);

    return _write(SyncClockCommand(clock.now()));
  }

  @override
  Future<void> disconnect() => _adapter.disconnect();

  @override
  Stream<PpgPacket> get livePackets => _frames
      .where((f) => f is PpgDataFrame && f.packet.kind == PpgPacketKind.live)
      .map((f) => (f as PpgDataFrame).packet);

  @override
  Stream<DeviceStatus> get statusUpdates =>
      _adapter.statusNotifications.expand((raw) {
        switch (_codec.decodeStatus(raw)) {
          case Ok(:final value):
            return [value];
          case Err(:final failure):
            _protocolErrors.add(failure);
            return const <DeviceStatus>[];
        }
      });

  @override
  Future<Result<DeviceStatus, Failure>> readStatus() async {
    switch (await _adapter.readStatus()) {
      case Ok(:final value):
        return _codec.decodeStatus(value);
      case Err(:final failure):
        return Err(failure);
    }
  }

  @override
  Future<Result<void, Failure>> startStreaming() =>
      _write(const StartStreamingCommand());

  @override
  Future<Result<void, Failure>> stopStreaming() =>
      _write(const StopStreamingCommand());

  @override
  Stream<PpgPacket> downloadHistory(
    int fromSequence,
    int toSequence, {
    Duration idleTimeout = const Duration(seconds: 5),
  }) {
    late final StreamController<PpgPacket> controller;
    StreamSubscription<PpgFrame>? frames;
    StreamSubscription<DeviceLinkState>? link;
    Timer? idle;

    void finish([Failure? failure]) {
      idle?.cancel();
      unawaited(frames?.cancel());
      unawaited(link?.cancel());
      if (controller.isClosed) return;
      if (failure != null) controller.addError(failure);
      unawaited(controller.close());
    }

    void armIdle() {
      idle?.cancel();
      idle = Timer(
        idleTimeout,
        () => finish(const ProtocolError('History download timed out')),
      );
    }

    controller = StreamController<PpgPacket>(
      onListen: () async {
        frames = _frames.listen((frame) {
          switch (frame) {
            case PpgDataFrame(:final packet)
                when packet.kind == PpgPacketKind.history &&
                    packet.sequence >= fromSequence &&
                    packet.sequence <= toSequence:
              armIdle();
              controller.add(packet);
            case HistoryEndFrame(fromSequence: final f, toSequence: final t)
                when f == fromSequence && t == toSequence:
              finish();
            default:
              break;
          }
        });
        link = _adapter.linkState
            .where((s) => s == DeviceLinkState.disconnected)
            .listen(
              (_) => finish(
                const ConnectionLost('Link dropped during history download'),
              ),
            );
        armIdle();
        final written = await _write(
          RequestHistoryCommand(fromSequence, toSequence),
        );
        if (written case Err(:final failure)) finish(failure);
      },
      // Cancel without awaiting: the done event is delivered only after
      // onCancel's future completes, and an already-cancelled subscription
      // may hand back a root-zone future (stalls under fake_async).
      onCancel: () {
        idle?.cancel();
        unawaited(frames?.cancel());
        unawaited(link?.cancel());
      },
    );
    return controller.stream;
  }

  Future<Result<void, Failure>> _write(ControlCommand command) =>
      _adapter.writeControl(_codec.encodeCommand(command));
}
