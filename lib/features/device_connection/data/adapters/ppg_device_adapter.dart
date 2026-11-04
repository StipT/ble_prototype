import 'dart:typed_data';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/ble_types.dart';

/// Byte-level port to one PPG wearable. Implemented by `FakePpgDevice`
/// (simulator, tests) and `ReactiveBlePpgDeviceAdapter` (real radio via
/// `flutter_reactive_ble`); `core/di` picks one from the `USE_FAKE_DEVICE`
/// flag.
///
/// The adapter deliberately knows nothing about packet *contents*: it moves
/// opaque bytes to and from the three characteristics declared in
/// `PpgPacketCodec`. Keeping parsing out of the adapter means the fake and
/// the real radio are exercised by exactly the same decoding code.
///
/// ## Lifecycle the implementations must follow
/// 1. Wait for [adapterStatus] == `poweredOn` (iOS reports `unknown` for a
///    few hundred ms after app start — scanning then silently does nothing).
/// 2. [scan] with the service UUID filter, then stop scanning *before*
///    connecting: many Android stacks fail connects (status 133) while a
///    scan is running.
/// 3. [connect] — link-layer connect + service discovery + subscribe (CCCD
///    write) to the PPG and status characteristics.
/// 4. [requestMtu] — Android only does anything; iOS auto-negotiates.
/// 5. Exchange data: notifications in, [writeControl] out.
/// 6. On an unexpected drop [linkState] emits `disconnected`; the caller owns
///    the reconnect policy (backoff), not the adapter.
///
/// Streams are broadcast so several blocs can listen at once.
abstract interface class PpgDeviceAdapter {
  /// Radio state. Emits the current value immediately on listen, then every
  /// change (user toggles Bluetooth, airplane mode, permission revoked).
  Stream<BluetoothAdapterStatus> get adapterStatus;

  /// Scans for wearables advertising `PpgPacketCodec.serviceUuid`.
  ///
  /// The stream completes after [timeout]; always bound scans in time — a
  /// running scan drains the battery and Android throttles apps that start
  /// more than 5 scans per 30 seconds (scans then return nothing, silently).
  /// Duplicate advertisements of the same device are emitted again with a
  /// fresh RSSI; de-duplicate by `id` in the caller.
  ///
  /// Errors are emitted as [Failure]s: [BluetoothOff],
  /// [BlePermissionDenied].
  Stream<DiscoveredPpgDevice> scan({
    Duration timeout = const Duration(seconds: 5),
  });

  /// Current link state; emits the current value immediately on listen.
  Stream<DeviceLinkState> get linkState;

  /// Synchronous snapshot of [linkState].
  DeviceLinkState get currentLinkState;

  /// ID of the connected (or connecting) device, if any.
  String? get connectedDeviceId;

  /// Connects to [deviceId], discovers services and enables notifications.
  ///
  /// [deviceId] is the OS identifier from a scan (MAC on Android, per-phone
  /// UUID on iOS). [timeout] bounds the attempt: Android has a hidden ~30 s
  /// connect timeout and iOS waits *forever* for an out-of-range device, so
  /// an explicit timeout is mandatory for a responsive UI.
  ///
  /// Returns [DeviceNotFound] when nothing answers in time, [BluetoothOff],
  /// or [ConnectionLost] if the link drops during setup.
  Future<Result<void, Failure>> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  });

  /// Gracefully tears the link down. Safe to call when not connected.
  Future<void> disconnect();

  /// Asks for an ATT MTU of [mtu] bytes and returns the negotiated value.
  ///
  /// Payload per notification = MTU - 3. Android starts at 23 and must call
  /// `requestMtu` (max 517) once per connection; iOS negotiates on its own
  /// (usually 185+) and ignores the request, so implementations just report
  /// the current value there. The peripheral may grant less than asked.
  Future<Result<int, Failure>> requestMtu(int mtu);

  /// Raw notifications from the PPG characteristic. Only emits while
  /// connected; survives reconnects (callers do not need to re-listen).
  Stream<Uint8List> get ppgNotifications;

  /// Raw notifications from the status characteristic.
  Stream<Uint8List> get statusNotifications;

  /// One-shot GATT read of the status characteristic.
  ///
  /// Reads are needed because notifications only arrive on *change*: right
  /// after connecting you would otherwise not know the battery level.
  Future<Result<Uint8List, Failure>> readStatus();

  /// Writes [bytes] to the control characteristic *with response*.
  ///
  /// With-response writes wait for the peripheral's ATT Write Response, so a
  /// successful future means the firmware received the command. Without
  /// response would be faster but can be dropped silently (and on iOS is
  /// flow-controlled via `canSendWriteWithoutResponse`). Returns
  /// [ConnectionLost] when not connected.
  Future<Result<void, Failure>> writeControl(Uint8List bytes);
}
