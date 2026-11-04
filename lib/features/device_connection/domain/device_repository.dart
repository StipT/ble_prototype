import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import 'entities/ble_types.dart';
import 'entities/device_status.dart';
import 'entities/ppg_packet.dart';

/// Domain-level view of the PPG wearable: decoded packets and typed
/// commands, no bytes and no UUIDs.
///
/// Implemented by `DeviceRepositoryImpl`, which combines a
/// `PpgDeviceAdapter` (fake or real radio) with `PpgPacketCodec`.
/// Stream errors are always [Failure] instances.
abstract interface class DeviceRepository {
  /// Phone Bluetooth radio state (current value first).
  Stream<BluetoothAdapterStatus> get adapterStatus;

  /// Scans for [timeout] and returns the de-duplicated devices found, sorted
  /// by signal strength. Returns [BluetoothOff] / [BlePermissionDenied] when
  /// scanning is impossible; an empty list is *not* an error.
  Future<Result<List<DiscoveredPpgDevice>, Failure>> scan({
    Duration timeout = const Duration(seconds: 4),
  });

  /// Link state (current value first).
  Stream<DeviceLinkState> get linkState;

  /// Synchronous link state snapshot.
  DeviceLinkState get currentLinkState;

  /// OS identifier of the connected device, `null` when disconnected.
  String? get connectedDeviceId;

  /// Connects to [deviceId] and prepares the link for streaming: negotiates
  /// the MTU and syncs the device clock. Returns [DeviceNotFound],
  /// [BluetoothOff] or [ConnectionLost].
  Future<Result<void, Failure>> connect(String deviceId);

  /// Gracefully disconnects.
  Future<void> disconnect();

  /// Decoded live packets (only `PpgPacketKind.live`). Malformed
  /// notifications are skipped and reported on [protocolErrors].
  Stream<PpgPacket> get livePackets;

  /// Every notification that failed to decode.
  Stream<ProtocolError> get protocolErrors;

  /// Battery/status notifications.
  Stream<DeviceStatus> get statusUpdates;

  /// One-shot status read.
  Future<Result<DeviceStatus, Failure>> readStatus();

  /// Tells the device to start pushing live packets.
  Future<Result<void, Failure>> startStreaming();

  /// Tells the device to stop pushing live packets.
  Future<Result<void, Failure>> stopStreaming();

  /// Requests the inclusive range [fromSequence]..[toSequence] from the
  /// device backlog and emits the replayed packets; completes when the
  /// device signals the end of the replay.
  ///
  /// Errors with [ConnectionLost] if the link drops mid-transfer (packets
  /// received so far are still valid — persist them as they arrive) or with
  /// [ProtocolError] if the device stops answering for [idleTimeout].
  Stream<PpgPacket> downloadHistory(
    int fromSequence,
    int toSequence, {
    Duration idleTimeout = const Duration(seconds: 5),
  });
}
