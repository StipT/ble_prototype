import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Result;

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../../core/stream/stream_extensions.dart';
import '../../domain/ble_failure_mapping.dart';
import '../../domain/entities/ble_types.dart';
import '../protocol/ppg_packet_codec.dart';
import 'ble_client.dart';
import 'ppg_device_adapter.dart';

/// [PpgDeviceAdapter] for real hardware, built on `flutter_reactive_ble`.
///
/// Everything here is "plumbing": it maps the plugin's reactive API onto
/// the app's port and turns plugin exceptions into typed [Failure]s. Packet
/// parsing stays in `PpgPacketCodec`, exactly as with `FakePpgDevice`.
///
/// ## Connection lifecycle (the #1 flutter_reactive_ble gotcha)
/// `connectToDevice` returns a stream, and **the BLE link only exists while
/// that stream has a listener**. Cancel the subscription — or let it be
/// garbage-collected — and the plugin disconnects. The adapter therefore
/// stores the subscription in a field for the whole connection lifetime
/// and only cancels it in [disconnect] or when the link is reported lost.
///
/// ```
///   connect()                         disconnect() / link lost
///      │                                       │
///      ▼                                       ▼
///  connectToDevice().listen ──► connecting ─► connected ─► (sub.cancel)
///                                     │            │
///                                     │            └─ subscribe ppg/status
///                                     │               (CCCD writes)
///                                     └─ timeout ─► DeviceNotFound
/// ```
///
/// ## Notifications vs indications
/// Both let the peripheral *push* values after the central wrote the
/// characteristic's CCCD descriptor (done for us by
/// `subscribeToCharacteristic`). **Notifications** are fire-and-forget (high
/// throughput, a packet can be lost at the link layer only if the link
/// drops); **indications** require an ATT confirmation per value (one value
/// per connection event — far too slow for 50 Hz PPG). The PPG and status
/// characteristics use notifications; the plugin handles either
/// transparently.
///
/// ## Android vs iOS identifiers
/// Android identifies peripherals by MAC address; iOS hides MACs and hands
/// out a per-phone random UUID. A MAC written on an NFC tag is therefore
/// meaningless on iOS: [connect] resolves it by scanning for the PPG
/// service and matching the advertised name (see [connect]).
class ReactiveBlePpgDeviceAdapter implements PpgDeviceAdapter {
  /// Creates the adapter.
  ///
  /// [client] is the BLE seam (defaults to the real plugin; tests pass a
  /// mock). [platform] overrides `defaultTargetPlatform` so the iOS MAC
  /// resolution path is testable on any host. [idResolutionScan] bounds the
  /// extra scan used on iOS to turn a MAC into a CoreBluetooth UUID.
  ReactiveBlePpgDeviceAdapter({
    BleClient? client,
    TargetPlatform? platform,
    this.idResolutionScan = const Duration(seconds: 4),
  }) : _client = client ?? FlutterReactiveBleClient(),
       _platform = platform ?? defaultTargetPlatform;

  final BleClient _client;
  final TargetPlatform _platform;

  /// How long [connect] scans on iOS to find the peripheral behind a MAC
  /// address (e.g. one read from an NFC pairing tag).
  final Duration idResolutionScan;

  static final _serviceUuid = Uuid.parse(PpgPacketCodec.serviceUuid);
  static final _ppgUuid = Uuid.parse(PpgPacketCodec.ppgCharacteristicUuid);
  static final _controlUuid = Uuid.parse(
    PpgPacketCodec.controlCharacteristicUuid,
  );
  static final _statusUuid = Uuid.parse(
    PpgPacketCodec.statusCharacteristicUuid,
  );
  static final _mac = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');

  final _ppgController = StreamController<Uint8List>.broadcast();
  final _statusController = StreamController<Uint8List>.broadcast();
  final _linkController = StreamController<DeviceLinkState>.broadcast();

  DeviceLinkState _link = DeviceLinkState.disconnected;

  /// The id the caller asked for (may be a MAC on iOS).
  String? _requestedId;

  /// The id actually used for GATT operations (resolved UUID on iOS).
  String? _gattId;

  /// iOS only: MAC → CoreBluetooth UUID learned by earlier resolutions, so
  /// reconnects skip the extra scan.
  final _resolvedIds = <String, String>{};

  /// Keeps the link alive — see the class docs.
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _ppgSub;
  StreamSubscription<List<int>>? _statusSub;

  /// Completes the in-flight [connect] call, if any.
  void Function(Result<void, Failure>)? _finishConnect;

  /// Bumped on every connect/disconnect so callbacks of an older link can
  /// recognise they are stale and do nothing.
  int _generation = 0;

  // ---------------------------------------------------------------------------
  // Adapter status
  // ---------------------------------------------------------------------------

  /// Maps the plugin's [BleStatus] onto [BluetoothAdapterStatus].
  ///
  /// `locationServicesDisabled` (Android ≤ 11: BLE scanning requires the
  /// system location toggle) is reported as `poweredOff`, because the fix is
  /// the same kind of action — flip a system switch — and scanning finds
  /// nothing until then.
  @override
  Stream<BluetoothAdapterStatus> get adapterStatus =>
      _client.statusStream.map(_mapStatus);

  static BluetoothAdapterStatus _mapStatus(BleStatus status) =>
      switch (status) {
        BleStatus.ready => BluetoothAdapterStatus.poweredOn,
        BleStatus.poweredOff ||
        BleStatus.locationServicesDisabled => BluetoothAdapterStatus.poweredOff,
        BleStatus.unauthorized => BluetoothAdapterStatus.unauthorized,
        BleStatus.unsupported => BluetoothAdapterStatus.unsupported,
        BleStatus.unknown => BluetoothAdapterStatus.unknown,
      };

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Scans for peripherals advertising the PPG service for [timeout].
  ///
  /// The OS-level filter (`withServices`) lets the radio controller drop
  /// unrelated advertisements in hardware and is *required* for background
  /// scanning on iOS. Some Android chipsets ignore 128-bit UUID filters, so
  /// results are filtered again here when the advertisement lists its
  /// services. `ScanMode.lowLatency` (Android) scans continuously — fine for
  /// a short, user-initiated scan, too power hungry for a long one.
  ///
  /// Plugin errors are mapped with [mapBleError] (e.g. "location services
  /// disabled" → [BluetoothOff], missing `BLUETOOTH_SCAN` →
  /// [BlePermissionDenied]) and close the stream.
  @override
  Stream<DiscoveredPpgDevice> scan({
    Duration timeout = const Duration(seconds: 5),
  }) {
    late final StreamController<DiscoveredPpgDevice> controller;
    StreamSubscription<DiscoveredDevice>? sub;
    Timer? timer;

    Future<void> stop() async {
      timer?.cancel();
      final s = sub;
      sub = null;
      await s?.cancel();
    }

    controller = StreamController<DiscoveredPpgDevice>(
      onListen: () {
        sub = _client
            .scanForDevices(
              withServices: [_serviceUuid],
              scanMode: ScanMode.lowLatency,
            )
            .listen(
              (d) {
                if (!_advertisesPpgService(d)) return;
                controller.add(
                  DiscoveredPpgDevice(id: d.id, name: d.name, rssi: d.rssi),
                );
              },
              onError: (Object e) {
                controller.addError(mapBleError(e));
                unawaited(stop());
                unawaited(controller.close());
              },
              onDone: () {
                timer?.cancel();
                unawaited(controller.close());
              },
            );
        timer = Timer(timeout, () {
          unawaited(stop());
          unawaited(controller.close());
        });
      },
      onCancel: stop,
    );
    return controller.stream;
  }

  /// Defensive second filter. An empty service list is accepted: iOS and
  /// some Android stacks put the service UUID in the *scan response* and may
  /// report only the primary advertisement.
  static bool _advertisesPpgService(DiscoveredDevice d) =>
      d.serviceUuids.isEmpty || d.serviceUuids.contains(_serviceUuid);

  // ---------------------------------------------------------------------------
  // Link
  // ---------------------------------------------------------------------------

  @override
  Stream<DeviceLinkState> get linkState =>
      _linkController.stream.startWith(() => _link);

  @override
  DeviceLinkState get currentLinkState => _link;

  /// The id passed to [connect] (a MAC stays a MAC even on iOS, so callers
  /// can compare it with what they persisted).
  @override
  String? get connectedDeviceId =>
      _link == DeviceLinkState.disconnected ? null : _requestedId;

  /// Connects to [deviceId] and enables PPG + status notifications.
  ///
  /// Steps:
  /// 1. Drop any previous link (one wearable at a time).
  /// 2. iOS only: if [deviceId] is a MAC (Android-style id, e.g. from an NFC
  ///    tag), resolve it to a CoreBluetooth UUID by scanning for the PPG
  ///    service for [idResolutionScan]. A device whose advertised name
  ///    contains the last two MAC bytes (`…:EE:FF` → "EEFF", a common
  ///    firmware naming scheme) wins immediately; otherwise the only PPG
  ///    device in range is used. Ambiguity → [DeviceNotFound].
  /// 3. `connectToDevice` with partial service discovery (iOS discovers only
  ///    the PPG service — faster) and the plugin's `connectionTimeout`
  ///    (which also turns off Android's slow `autoConnect`).
  /// 4. On `connected`, subscribe to the PPG and status characteristics;
  ///    the plugin writes each CCCD descriptor to enable notifications.
  ///
  /// [timeout] is also enforced by a local timer because iOS would wait
  /// forever for an absent peripheral. Failures: [DeviceNotFound] (timeout,
  /// failed to connect, unresolvable id), [ConnectionLost] (dropped during
  /// setup or superseded by [disconnect]), plus anything [mapBleError]
  /// recognises (permission, Bluetooth off).
  @override
  Future<Result<void, Failure>> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_link == DeviceLinkState.connected && _requestedId == deviceId) {
      return okVoid;
    }
    await _teardown(const ConnectionLost('Superseded by a new connect'));
    final generation = ++_generation;
    _requestedId = deviceId;
    _setLink(DeviceLinkState.connecting);

    final String? resolved;
    try {
      resolved = await _resolveId(deviceId);
    } catch (e) {
      if (generation == _generation) _onLinkLost(generation);
      return Err(mapBleError(e));
    }
    if (generation != _generation) {
      return const Err(ConnectionLost('Connect cancelled'));
    }
    if (resolved == null) {
      _onLinkLost(generation);
      return Err(DeviceNotFound('No advertising PPG device matches $deviceId'));
    }
    _gattId = resolved;

    final completer = Completer<Result<void, Failure>>();
    void finish(Result<void, Failure> r) {
      if (!completer.isCompleted) completer.complete(r);
    }

    _finishConnect = finish;
    final timer = Timer(timeout, () {
      if (completer.isCompleted || generation != _generation) return;
      finish(_timeoutFailure(deviceId, timeout));
      _onLinkLost(generation);
    });

    _connectionSub = _client
        .connectToDevice(
          id: resolved,
          servicesWithCharacteristicsToDiscover: {
            _serviceUuid: [_ppgUuid, _controlUuid, _statusUuid],
          },
          connectionTimeout: timeout,
        )
        .listen(
          (update) => _onConnectionUpdate(update, generation, finish),
          onError: (Object e) {
            if (generation != _generation) return;
            finish(
              e is TimeoutException
                  ? _timeoutFailure(deviceId, timeout)
                  : Err(mapBleError(e)),
            );
            _onLinkLost(generation);
          },
          onDone: () {
            if (generation != _generation) return;
            finish(const Err(ConnectionLost('Connection stream closed')));
            _onLinkLost(generation);
          },
        );

    final result = await completer.future;
    timer.cancel();
    if (identical(_finishConnect, finish)) _finishConnect = null;
    return result;
  }

  void _onConnectionUpdate(
    ConnectionStateUpdate update,
    int generation,
    void Function(Result<void, Failure>) finish,
  ) {
    if (generation != _generation) return;
    switch (update.connectionState) {
      case DeviceConnectionState.connecting:
        _setLink(DeviceLinkState.connecting);
      case DeviceConnectionState.connected:
        _enableNotifications(generation);
        _setLink(DeviceLinkState.connected);
        finish(okVoid);
      case DeviceConnectionState.disconnecting:
        _setLink(DeviceLinkState.disconnecting);
      case DeviceConnectionState.disconnected:
        final message = update.failure?.message ?? 'Link dropped';
        // Never connected → the peripheral didn't answer; otherwise a
        // previously healthy link was lost.
        finish(
          update.failure?.code == ConnectionError.failedToConnect
              ? Err(DeviceNotFound(message))
              : Err(ConnectionLost(message)),
        );
        _onLinkLost(generation);
    }
  }

  /// Subscribes to the notify characteristics. Each subscription is the
  /// "notifications on" switch: cancelling it writes the CCCD back to off.
  /// A failing subscription (CCCD write rejected, characteristic missing)
  /// leaves the device unusable, so it is treated as a lost link and the
  /// caller's reconnect policy takes over.
  void _enableNotifications(int generation) {
    void onError(Object _) {
      if (generation == _generation) _onLinkLost(generation);
    }

    _ppgSub = _client
        .subscribeToCharacteristic(_characteristic(_ppgUuid))
        .listen(
          (v) => _ppgController.add(Uint8List.fromList(v)),
          onError: onError,
        );
    _statusSub = _client
        .subscribeToCharacteristic(_characteristic(_statusUuid))
        .listen(
          (v) => _statusController.add(Uint8List.fromList(v)),
          onError: onError,
        );
  }

  /// Unexpected link loss: release everything and report `disconnected`.
  void _onLinkLost(int generation) {
    if (generation != _generation) return;
    _generation++;
    unawaited(_teardown(const ConnectionLost('Link lost during connect')));
    _setLink(DeviceLinkState.disconnected);
  }

  /// Tears the link down gracefully; completes once the plugin released it.
  ///
  /// Cancelling the `connectToDevice` subscription is how
  /// flutter_reactive_ble disconnects — there is no `disconnect()` method.
  @override
  Future<void> disconnect() async {
    if (_connectionSub == null && _link == DeviceLinkState.disconnected) {
      return;
    }
    _generation++;
    _setLink(DeviceLinkState.disconnecting);
    await _teardown(const ConnectionLost('Disconnected by the app'));
    _setLink(DeviceLinkState.disconnected);
  }

  /// Cancels all subscriptions (fields are cleared *before* cancelling so a
  /// subscription is never cancelled twice) and fails a pending [connect]
  /// with [pendingFailure].
  Future<void> _teardown(Failure pendingFailure) async {
    final finish = _finishConnect;
    _finishConnect = null;
    finish?.call(Err(pendingFailure));
    final subs = [_ppgSub, _statusSub, _connectionSub];
    _ppgSub = _statusSub = null;
    _connectionSub = null;
    _gattId = null;
    // Cancel all synchronously first, then wait for the plugin to finish.
    await Future.wait([for (final s in subs) ?s?.cancel()]);
  }

  /// Resolves [deviceId] to an id usable with this platform's BLE stack.
  Future<String?> _resolveId(String deviceId) async {
    if (_platform != TargetPlatform.iOS || !_mac.hasMatch(deviceId)) {
      return deviceId;
    }
    final cached = _resolvedIds[deviceId];
    if (cached != null) return cached;

    final suffix = deviceId.replaceAll(':', '').substring(8).toUpperCase();
    final candidates = <String, DiscoveredPpgDevice>{};
    await for (final d in scan(timeout: idResolutionScan)) {
      if (d.name.toUpperCase().contains(suffix)) {
        candidates
          ..clear()
          ..[d.id] = d;
        break;
      }
      candidates[d.id] = d;
    }
    if (candidates.length != 1) return null;
    return _resolvedIds[deviceId] = candidates.keys.single;
  }

  // ---------------------------------------------------------------------------
  // GATT operations
  // ---------------------------------------------------------------------------

  /// Requests an ATT MTU of [mtu] bytes.
  ///
  /// The ATT MTU is the largest ATT packet; each notification carries at
  /// most MTU − 3 bytes of payload (3-byte ATT header). Android defaults to
  /// 23 (→ 20-byte payloads) until the app asks; iOS negotiates on its own
  /// and the plugin simply reports the current value there.
  @override
  Future<Result<int, Failure>> requestMtu(int mtu) async {
    final id = _gattId;
    if (_link != DeviceLinkState.connected || id == null) {
      return const Err(ConnectionLost('Not connected'));
    }
    try {
      return Ok(await _client.requestMtu(deviceId: id, mtu: mtu));
    } catch (e) {
      return Err(mapBleError(e));
    }
  }

  @override
  Stream<Uint8List> get ppgNotifications => _ppgController.stream;

  @override
  Stream<Uint8List> get statusNotifications => _statusController.stream;

  /// Reads the status characteristic (battery, charging, stored range).
  @override
  Future<Result<Uint8List, Failure>> readStatus() async {
    final id = _gattId;
    if (_link != DeviceLinkState.connected || id == null) {
      return const Err(ConnectionLost('Not connected'));
    }
    try {
      final bytes = await _client.readCharacteristic(
        _characteristic(_statusUuid),
      );
      return Ok(Uint8List.fromList(bytes));
    } catch (e) {
      return Err(mapBleError(e));
    }
  }

  /// Writes [bytes] to the control characteristic *with response*.
  ///
  /// Commands (start/stop streaming, set clock, request history) are rare
  /// and must not be lost, so the ATT Write Request/Response round trip
  /// (~1 connection interval) is worth it. Write *without* response (ATT
  /// Write Command) is for bulk uploads like firmware updates.
  @override
  Future<Result<void, Failure>> writeControl(Uint8List bytes) async {
    final id = _gattId;
    if (_link != DeviceLinkState.connected || id == null) {
      return const Err(ConnectionLost('Not connected'));
    }
    try {
      await _client.writeCharacteristicWithResponse(
        _characteristic(_controlUuid),
        value: bytes,
      );
      return okVoid;
    } catch (e) {
      return Err(mapBleError(e));
    }
  }

  QualifiedCharacteristic _characteristic(Uuid id) => QualifiedCharacteristic(
    characteristicId: id,
    serviceId: _serviceUuid,
    deviceId: _gattId ?? '',
  );

  void _setLink(DeviceLinkState state) {
    if (_link == state) return;
    _link = state;
    if (!_linkController.isClosed) _linkController.add(state);
  }

  /// Releases the link and closes all streams. Call when the adapter is
  /// unregistered from DI (app shutdown / tests).
  Future<void> dispose() async {
    _generation++;
    await _teardown(const ConnectionLost('Adapter disposed'));
    _link = DeviceLinkState.disconnected;
    await Future.wait([
      _ppgController.close(),
      _statusController.close(),
      _linkController.close(),
    ]);
  }
}

/// [DeviceNotFound] result for a connect to [deviceId] that exceeded
/// [timeout] (device out of range, powered off, or busy with another
/// central).
Result<void, Failure> _timeoutFailure(String deviceId, Duration timeout) => Err(
  DeviceNotFound(
    'No answer from $deviceId within ${timeout.inMilliseconds} ms',
  ),
);
