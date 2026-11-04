import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../../core/stream/stream_extensions.dart';
import '../../domain/entities/ble_types.dart';
import '../../domain/entities/device_status.dart';
import '../../domain/entities/ppg_packet.dart';
import '../adapters/ppg_device_adapter.dart';
import '../protocol/ppg_packet_codec.dart';
import 'ppg_signal_generator.dart';

/// In-process simulation of the PPG wearable, speaking the exact same bytes
/// as the real firmware (it encodes with `PpgPacketCodec`), so the whole
/// decode → bloc → database path is exercised without hardware.
///
/// Behaviour modelled after typical wearable firmware:
/// * It is "powered on" from construction: a timer produces one packet of
///   [PpgPacketCodec.samplesPerPacket] samples every 100 ms (50 Hz) and
///   stores it in a ring buffer of [backlogCapacity] packets — *whether or
///   not* a phone is connected. That ring buffer is the **stored backlog**
///   the app downloads after reconnecting.
/// * Live notifications are only sent while connected, after the app wrote
///   the start command, and only if they fit into the negotiated MTU
///   (oversize payloads are truncated like a real stack would, which the
///   codec then rejects — forget `requestMtu` and you will see it).
/// * Faults for the debug panel: [simulateDisconnect], [simulateOutage],
///   [dropNextPackets], [packetDropProbability], [randomDisconnectsPerMinute],
///   [bluetoothEnabled].
///
/// Timers use `dart:async` and time comes from `package:clock`, so tests can
/// drive it deterministically with `fake_async`.
class FakePpgDevice implements PpgDeviceAdapter {
  /// Creates and powers on the simulated device.
  ///
  /// [codec] encodes frames; [generator] produces the signal (inject a seeded
  /// one for deterministic tests); [deviceId]/[deviceName] are what scanning
  /// reports; [backlogCapacity] is the ring-buffer size in packets (3000 =
  /// 5 minutes); [random] drives fault injection; [scanLatency] and
  /// [connectLatency] imitate radio timing; [autoPowerOn] = false lets tests
  /// start the clock explicitly via [powerOn].
  FakePpgDevice({
    PpgPacketCodec codec = const PpgPacketCodec(),
    PpgSignalGenerator? generator,
    this.deviceId = defaultDeviceId,
    this.deviceName = 'PPG-Fake-0001',
    this.backlogCapacity = 3000,
    math.Random? random,
    this.scanLatency = const Duration(milliseconds: 400),
    this.connectLatency = const Duration(milliseconds: 300),
    bool autoPowerOn = true,
  }) : _codec = codec,
       _random = random ?? math.Random(),
       _generator =
           generator ??
           PpgSignalGenerator(sampleRateHz: PpgPacketCodec.sampleRateHz) {
    if (autoPowerOn) powerOn();
  }

  /// ID reported by the fake scan and stored on the fake NFC tag. Formatted
  /// like an Android MAC address.
  static const defaultDeviceId = 'FA:KE:00:00:00:01';

  /// Time between two packets: samplesPerPacket / sampleRate.
  static const packetInterval = Duration(
    microseconds:
        PpgPacketCodec.samplesPerPacket *
        Duration.microsecondsPerSecond ~/
        PpgPacketCodec.sampleRateHz,
  );

  /// Default ATT MTU before negotiation (BLE 4.0 minimum).
  static const defaultMtu = 23;

  /// Scan / connect identifier.
  final String deviceId;

  /// Advertised name.
  final String deviceName;

  /// Ring buffer size, in packets.
  final int backlogCapacity;

  /// Delay before the first advertisement is "heard".
  final Duration scanLatency;

  /// Delay of a successful connection.
  final Duration connectLatency;

  final PpgPacketCodec _codec;
  final PpgSignalGenerator _generator;
  final math.Random _random;

  final _ppgController = StreamController<Uint8List>.broadcast();
  final _statusController = StreamController<Uint8List>.broadcast();
  final _linkController = StreamController<DeviceLinkState>.broadcast();
  final _adapterController =
      StreamController<BluetoothAdapterStatus>.broadcast();

  final ListQueue<PpgPacket> _backlog = ListQueue();
  Timer? _ticker;
  int _nextSequence = 0;
  int _tickCount = 0;
  int _dropNext = 0;
  int _replayGeneration = 0;
  bool _streaming = false;
  bool _inRange = true;
  bool _charging = false;
  double _battery = 100;
  int _mtu = defaultMtu;
  Duration _clockOffset = Duration.zero;
  DeviceLinkState _link = DeviceLinkState.disconnected;
  BluetoothAdapterStatus _adapter = BluetoothAdapterStatus.poweredOn;
  Timer? _outageTimer;

  // ---------------------------------------------------------------------------
  // Fault injection / debug knobs
  // ---------------------------------------------------------------------------

  /// Probability (0..1) that any live notification is lost in the air.
  /// Lost packets stay in the backlog and can be fetched by history sync.
  double packetDropProbability = 0;

  /// Expected number of spontaneous link drops per minute while connected.
  double randomDisconnectsPerMinute = 0;

  /// Simulated pulse rate.
  double get heartRateBpm => _generator.heartRateBpm;
  set heartRateBpm(double bpm) => _generator.heartRateBpm = bpm;

  /// Whether the phone's Bluetooth radio is on. Turning it off drops the
  /// link, like the real OS does.
  bool get bluetoothEnabled => _adapter == BluetoothAdapterStatus.poweredOn;
  set bluetoothEnabled(bool enabled) {
    if (!enabled) _dropLink();
    _setAdapter(
      enabled
          ? BluetoothAdapterStatus.poweredOn
          : BluetoothAdapterStatus.poweredOff,
    );
  }

  /// Whether the simulated device sits on its charger.
  bool get charging => _charging;
  set charging(bool value) {
    _charging = value;
    _notifyStatus();
  }

  /// Whether the device is reachable (advertising and accepting connects).
  bool get isInRange => _inRange;

  /// Packets currently held in the device backlog.
  int get backlogLength => _backlog.length;

  /// Sequence number of the next packet to be produced.
  int get nextSequence => _nextSequence;

  /// Whether the device has been told to stream.
  bool get isStreaming => _streaming;

  /// Currently negotiated MTU.
  int get mtu => _mtu;

  /// Silently drops the next [count] live notifications (creates a
  /// sequence gap that history sync must fill).
  void dropNextPackets(int count) => _dropNext += count;

  /// Drops the link immediately, as if the supervision timeout fired. The
  /// device stays in range, so a reconnect will succeed.
  void simulateDisconnect() => _dropLink();

  /// Drops the link and refuses connections for [duration] (user walked
  /// away). Exercises the reconnect backoff.
  void simulateOutage(Duration duration) {
    _dropLink();
    _inRange = false;
    _outageTimer?.cancel();
    _outageTimer = Timer(duration, () => _inRange = true);
  }

  /// Starts producing packets (called by the constructor unless
  /// `autoPowerOn: false`).
  void powerOn() {
    _ticker ??= Timer.periodic(packetInterval, (_) => _tick());
  }

  /// Stops all timers and closes streams. Idempotent.
  ///
  /// Close futures are not awaited: a broadcast controller's `done` future
  /// only completes once listeners received the done event, which would tie
  /// disposal to the listeners' lifecycle.
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _outageTimer?.cancel();
    for (final c in [
      _ppgController,
      _statusController,
      _linkController,
      _adapterController,
    ]) {
      unawaited(c.close());
    }
  }

  // ---------------------------------------------------------------------------
  // PpgDeviceAdapter
  // ---------------------------------------------------------------------------

  @override
  Stream<BluetoothAdapterStatus> get adapterStatus =>
      _adapterController.stream.startWith(() => _adapter);

  @override
  Stream<DeviceLinkState> get linkState =>
      _linkController.stream.startWith(() => _link);

  @override
  DeviceLinkState get currentLinkState => _link;

  @override
  String? get connectedDeviceId =>
      _link == DeviceLinkState.disconnected ? null : deviceId;

  @override
  Stream<DiscoveredPpgDevice> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    if (!bluetoothEnabled) throw const BluetoothOff();
    const advertisingInterval = Duration(seconds: 1);
    var elapsed = Duration.zero;
    var wait = scanLatency < timeout ? scanLatency : timeout;
    while (true) {
      await Future<void>.delayed(wait);
      elapsed += wait;
      if (!bluetoothEnabled) throw const BluetoothOff();
      if (elapsed > timeout) return;
      if (_inRange && _link == DeviceLinkState.disconnected) {
        yield DiscoveredPpgDevice(
          id: deviceId,
          name: deviceName,
          rssi: -50 - _random.nextInt(15),
        );
      }
      wait = advertisingInterval;
    }
  }

  @override
  Future<Result<void, Failure>> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!bluetoothEnabled) return const Err(BluetoothOff());
    if (_link == DeviceLinkState.connected && deviceId == this.deviceId) {
      return okVoid;
    }
    _setLink(DeviceLinkState.connecting);
    final wait = connectLatency < timeout ? connectLatency : timeout;
    await Future<void>.delayed(wait);
    if (_link != DeviceLinkState.connecting) {
      return const Err(ConnectionLost('Link dropped while connecting'));
    }
    if (deviceId != this.deviceId || !_inRange || !bluetoothEnabled) {
      _setLink(DeviceLinkState.disconnected);
      return Err(DeviceNotFound('No answer from $deviceId'));
    }
    _mtu = defaultMtu;
    _setLink(DeviceLinkState.connected);
    return okVoid;
  }

  @override
  Future<void> disconnect() async {
    if (_link == DeviceLinkState.disconnected) return;
    _setLink(DeviceLinkState.disconnecting);
    _streaming = false;
    _replayGeneration++;
    await Future<void>.delayed(Duration.zero);
    _setLink(DeviceLinkState.disconnected);
  }

  @override
  Future<Result<int, Failure>> requestMtu(int mtu) async {
    if (_link != DeviceLinkState.connected) return const Err(ConnectionLost());
    _mtu = math.max(defaultMtu, math.min(mtu, PpgPacketCodec.preferredMtu));
    return Ok(_mtu);
  }

  @override
  Stream<Uint8List> get ppgNotifications => _ppgController.stream;

  @override
  Stream<Uint8List> get statusNotifications => _statusController.stream;

  @override
  Future<Result<Uint8List, Failure>> readStatus() async {
    if (_link != DeviceLinkState.connected) return const Err(ConnectionLost());
    return Ok(_codec.encodeStatus(status));
  }

  @override
  Future<Result<void, Failure>> writeControl(Uint8List bytes) async {
    if (_link != DeviceLinkState.connected) return const Err(ConnectionLost());
    final decoded = _codec.decodeCommand(bytes);
    switch (decoded) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        switch (value) {
          case StartStreamingCommand():
            _streaming = true;
          case StopStreamingCommand():
            _streaming = false;
          case SyncClockCommand(:final now):
            _clockOffset = now.difference(clock.now());
          case RequestHistoryCommand(:final fromSequence, :final toSequence):
            unawaited(_replayHistory(fromSequence, toSequence));
        }
        _notifyStatus();
        return okVoid;
    }
  }

  // ---------------------------------------------------------------------------
  // Simulation internals
  // ---------------------------------------------------------------------------

  /// Current device status (also what the status characteristic returns).
  DeviceStatus get status => DeviceStatus(
    batteryPercent: _battery.round(),
    isStreaming: _streaming,
    isCharging: _charging,
    hasData: _backlog.isNotEmpty,
    oldestSequence: _backlog.isEmpty ? 0 : _backlog.first.sequence,
    latestSequence: _backlog.isEmpty ? 0 : _backlog.last.sequence,
  );

  void _tick() {
    _tickCount++;
    final packet = PpgPacket(
      sequence: _nextSequence++,
      timestamp: clock.now().add(_clockOffset).subtract(packetInterval),
      samples: _generator.next(PpgPacketCodec.samplesPerPacket),
    );
    _backlog.add(packet);
    while (_backlog.length > backlogCapacity) {
      _backlog.removeFirst();
    }

    _battery = math.max(0, _battery - 0.0005);

    if (_link != DeviceLinkState.connected) return;

    if (_streaming) {
      if (_dropNext > 0) {
        _dropNext--;
      } else if (_random.nextDouble() >= packetDropProbability) {
        _notifyPpg(_codec.encodePacket(packet));
      }
    }
    if (_tickCount % 10 == 0) _notifyStatus();

    final perTick =
        randomDisconnectsPerMinute *
        packetInterval.inMicroseconds /
        const Duration(minutes: 1).inMicroseconds;
    if (perTick > 0 && _random.nextDouble() < perTick) _dropLink();
  }

  Future<void> _replayHistory(int from, int to) async {
    final generation = ++_replayGeneration;
    var sent = 0;
    if (_backlog.isNotEmpty) {
      final oldest = _backlog.first.sequence;
      final start = math.max(from, oldest);
      final end = math.min(to, _backlog.last.sequence);
      for (var seq = start; seq <= end; seq++) {
        // Yield every few packets: a real link sends ~1 packet per
        // connection event (7.5–50 ms), never all at once.
        if (sent % 20 == 0) await Future<void>.delayed(Duration.zero);
        if (generation != _replayGeneration ||
            _link != DeviceLinkState.connected) {
          return;
        }
        final index = seq - _backlog.first.sequence;
        if (index < 0 || index >= _backlog.length) continue;
        final packet = _backlog.elementAt(index);
        _notifyPpg(
          _codec.encodePacket(packet.copyWith(kind: PpgPacketKind.history)),
        );
        sent++;
      }
    }
    await Future<void>.delayed(Duration.zero);
    if (generation != _replayGeneration || _link != DeviceLinkState.connected) {
      return;
    }
    _notifyPpg(
      _codec.encodeHistoryEnd(
        HistoryEndFrame(fromSequence: from, toSequence: to, sentCount: sent),
      ),
    );
  }

  void _notifyPpg(Uint8List frame) {
    final maxPayload = _mtu - PpgPacketCodec.attHeaderBytes;
    // A real stack truncates (or refuses) values larger than MTU - 3.
    _ppgController.add(
      frame.length > maxPayload
          ? Uint8List.sublistView(frame, 0, maxPayload)
          : frame,
    );
  }

  void _notifyStatus() {
    if (_link == DeviceLinkState.connected) {
      _statusController.add(_codec.encodeStatus(status));
    }
  }

  // Like real firmware, a lost link resets the streaming flag (CCCD
  // subscriptions of unbonded peers don't survive a disconnect either), so
  // the app must send the start command again after reconnecting.
  void _dropLink() {
    if (_link == DeviceLinkState.disconnected) return;
    _streaming = false;
    _replayGeneration++;
    _setLink(DeviceLinkState.disconnected);
  }

  void _setLink(DeviceLinkState state) {
    if (_link == state) return;
    _link = state;
    if (!_linkController.isClosed) _linkController.add(state);
  }

  void _setAdapter(BluetoothAdapterStatus status) {
    if (_adapter == status) return;
    _adapter = status;
    if (!_adapterController.isClosed) _adapterController.add(status);
  }
}
