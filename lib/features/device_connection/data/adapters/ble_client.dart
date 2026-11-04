import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Thin, mockable seam over the subset of [FlutterReactiveBle] the app uses.
///
/// [FlutterReactiveBle] is a singleton that talks to native code through
/// platform channels, so it cannot run in unit tests. Everything the
/// adapter needs goes through this interface instead; tests substitute a
/// `mocktail` mock and drive the streams by hand. Signatures intentionally
/// mirror the plugin 1:1 (same names, same model types) so the
/// production implementation [FlutterReactiveBleClient] is pure delegation
/// with zero logic worth testing.
///
/// ### GATT in one paragraph
/// A BLE peripheral exposes a **GATT** (Generic ATTribute profile) table:
/// *services* (identified by UUIDs) group *characteristics* (also UUIDs),
/// which are small values the central (the phone) can read, write, or
/// subscribe to. A [QualifiedCharacteristic] is the full address of one
/// value: device id + service UUID + characteristic UUID.
abstract interface class BleClient {
  /// State of the phone's Bluetooth stack (`ready`, `poweredOff`,
  /// `unauthorized`, ...). Emits the current value on listen, then changes.
  Stream<BleStatus> get statusStream;

  /// Starts a BLE scan that only reports peripherals advertising one of
  /// [withServices].
  ///
  /// The scan runs until the subscription is cancelled. [scanMode] is
  /// Android-only (duty cycle vs. latency trade-off; iOS ignores it). When
  /// [requireLocationServicesEnabled] is true the plugin fails fast on
  /// Android ≤ 11 if the location toggle is off — otherwise the scan would
  /// simply never find anything.
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  });

  /// Connects to the peripheral [id] and reports state changes.
  ///
  /// **The connection lives exactly as long as the returned stream's
  /// subscription** — cancelling it disconnects. [servicesWithCharacteristicsToDiscover]
  /// limits service discovery on iOS (faster connects; Android always
  /// discovers everything). [connectionTimeout] makes the attempt fail with
  /// a `TimeoutException`; on Android it also disables `autoConnect`, which
  /// would otherwise wait (slowly, opportunistically) forever.
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  });

  /// Negotiates the ATT MTU (max bytes per packet incl. 3-byte header) with
  /// [deviceId]; returns the value both sides agreed on.
  Future<int> requestMtu({required String deviceId, required int mtu});

  /// Enables notifications/indications on [characteristic] (the plugin
  /// writes the CCCD descriptor on listen) and emits every value pushed by
  /// the peripheral. Cancelling the subscription disables them again.
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  );

  /// One-shot ATT Read Request of [characteristic].
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic);

  /// ATT Write Request of [value] to [characteristic]: completes only after
  /// the peripheral acknowledged with a Write Response.
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  });
}

/// Production [BleClient]: forwards every call to [FlutterReactiveBle].
class FlutterReactiveBleClient implements BleClient {
  /// Wraps [ble]; defaults to the plugin's process-wide singleton.
  ///
  /// The singleton is created lazily on first use: constructing it starts
  /// listening to the native status channel, which must not happen merely
  /// because DI registered the adapter (e.g. in tests without plugins).
  FlutterReactiveBleClient([FlutterReactiveBle? ble]) : _injected = ble;

  final FlutterReactiveBle? _injected;
  late final FlutterReactiveBle _ble = _injected ?? FlutterReactiveBle();

  @override
  Stream<BleStatus> get statusStream => _ble.statusStream;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) => _ble.scanForDevices(
    withServices: withServices,
    scanMode: scanMode,
    requireLocationServicesEnabled: requireLocationServicesEnabled,
  );

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) => _ble.connectToDevice(
    id: id,
    servicesWithCharacteristicsToDiscover:
        servicesWithCharacteristicsToDiscover,
    connectionTimeout: connectionTimeout,
  );

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) =>
      _ble.requestMtu(deviceId: deviceId, mtu: mtu);

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) => _ble.subscribeToCharacteristic(characteristic);

  @override
  Future<List<int>> readCharacteristic(
    QualifiedCharacteristic characteristic,
  ) => _ble.readCharacteristic(characteristic);

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) => _ble.writeCharacteristicWithResponse(characteristic, value: value);
}
