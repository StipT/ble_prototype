import 'dart:async';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/device_connection/data/adapters/ble_client.dart';
import 'package:ble_prototype/features/device_connection/data/adapters/reactive_ble_ppg_device_adapter.dart';
import 'package:ble_prototype/features/device_connection/data/protocol/ppg_packet_codec.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ble_types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Result;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBleClient extends Mock implements BleClient {}

final _service = Uuid.parse(PpgPacketCodec.serviceUuid);
final _ppg = Uuid.parse(PpgPacketCodec.ppgCharacteristicUuid);
final _control = Uuid.parse(PpgPacketCodec.controlCharacteristicUuid);
final _status = Uuid.parse(PpgPacketCodec.statusCharacteristicUuid);

const _id = 'AA:BB:CC:DD:EE:FF';

DiscoveredDevice _device(String id, {String name = 'PPG', List<Uuid>? uuids}) =>
    DiscoveredDevice(
      id: id,
      name: name,
      serviceData: const {},
      manufacturerData: Uint8List(0),
      rssi: -60,
      serviceUuids: uuids ?? [_service],
    );

ConnectionStateUpdate _update(
  DeviceConnectionState state, {
  GenericFailure<ConnectionError>? failure,
}) => ConnectionStateUpdate(
  deviceId: _id,
  connectionState: state,
  failure: failure,
);

QualifiedCharacteristic _char(Uuid c, [String device = _id]) =>
    QualifiedCharacteristic(
      characteristicId: c,
      serviceId: _service,
      deviceId: device,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_char(_ppg));
    registerFallbackValue(<Uuid>[]);
    registerFallbackValue(ScanMode.balanced);
  });

  late _MockBleClient client;
  late StreamController<ConnectionStateUpdate> connection;
  late StreamController<List<int>> ppg;
  late StreamController<List<int>> status;
  late StreamController<DiscoveredDevice> scanResults;
  late ReactiveBlePpgDeviceAdapter adapter;

  ReactiveBlePpgDeviceAdapter build({TargetPlatform? platform}) =>
      ReactiveBlePpgDeviceAdapter(
        client: client,
        platform: platform ?? TargetPlatform.android,
        idResolutionScan: const Duration(seconds: 2),
      );

  setUp(() {
    client = _MockBleClient();
    connection = StreamController<ConnectionStateUpdate>();
    ppg = StreamController<List<int>>();
    status = StreamController<List<int>>();
    scanResults = StreamController<DiscoveredDevice>();
    when(
      () => client.connectToDevice(
        id: any(named: 'id'),
        servicesWithCharacteristicsToDiscover: any(
          named: 'servicesWithCharacteristicsToDiscover',
        ),
        connectionTimeout: any(named: 'connectionTimeout'),
      ),
    ).thenAnswer((_) => connection.stream);
    when(
      () => client.subscribeToCharacteristic(
        any(
          that: predicate<QualifiedCharacteristic>(
            (c) => c.characteristicId == _ppg,
          ),
        ),
      ),
    ).thenAnswer((_) => ppg.stream);
    when(
      () => client.subscribeToCharacteristic(
        any(
          that: predicate<QualifiedCharacteristic>(
            (c) => c.characteristicId == _status,
          ),
        ),
      ),
    ).thenAnswer((_) => status.stream);
    when(
      () => client.scanForDevices(
        withServices: any(named: 'withServices'),
        scanMode: any(named: 'scanMode'),
      ),
    ).thenAnswer((_) => scanResults.stream);
    adapter = build();
  });

  /// Connects and drives the plugin to `connected`.
  Future<Result<void, Failure>> connected(
    ReactiveBlePpgDeviceAdapter a, [
    String id = _id,
  ]) async {
    final future = a.connect(id);
    await pumpEventQueue();
    connection
      ..add(_update(DeviceConnectionState.connecting))
      ..add(_update(DeviceConnectionState.connected));
    return future;
  }

  group('adapterStatus', () {
    test('maps every BleStatus', () async {
      when(
        () => client.statusStream,
      ).thenAnswer((_) => Stream.fromIterable(BleStatus.values));
      expect(await adapter.adapterStatus.toList(), [
        BluetoothAdapterStatus.unknown,
        BluetoothAdapterStatus.unsupported,
        BluetoothAdapterStatus.unauthorized,
        BluetoothAdapterStatus.poweredOff,
        BluetoothAdapterStatus.poweredOff, // locationServicesDisabled
        BluetoothAdapterStatus.poweredOn,
      ]);
    });
  });

  group('scan', () {
    test('filters by the PPG service and stops after the timeout', () {
      fakeAsync((async) {
        final found = <DiscoveredPpgDevice>[];
        var done = false;
        adapter
            .scan(timeout: const Duration(seconds: 5))
            .listen(found.add, onDone: () => done = true);
        async.flushMicrotasks();

        final captured = verify(
          () => client.scanForDevices(
            withServices: captureAny(named: 'withServices'),
            scanMode: ScanMode.lowLatency,
          ),
        ).captured;
        expect(captured.single, [_service]);

        scanResults
          ..add(_device('A', name: 'PPG-A'))
          ..add(_device('B', uuids: [Uuid.parse('180d')]))
          ..add(_device('C', uuids: const []));
        async.flushMicrotasks();
        expect(found.map((d) => d.id), ['A', 'C']);
        expect(found.first.name, 'PPG-A');
        expect(found.first.rssi, -60);

        async.elapse(const Duration(seconds: 5));
        expect(done, isTrue);
        expect(scanResults.hasListener, isFalse);
      });
    });

    test('maps plugin errors to Failures and closes the stream', () async {
      final events = adapter.scan().toList();
      await pumpEventQueue();
      scanResults.addError(Exception('Location services are disabled'));
      await expectLater(events, throwsA(isA<BluetoothOff>()));
      await pumpEventQueue();
      expect(scanResults.hasListener, isFalse);
    });
  });

  group('connect', () {
    test('maps connection states and keeps the subscription alive', () async {
      final states = <DeviceLinkState>[];
      adapter.linkState.listen(states.add);

      final result = await connected(adapter);
      await pumpEventQueue();

      expect(result.isOk, isTrue);
      expect(adapter.currentLinkState, DeviceLinkState.connected);
      expect(adapter.connectedDeviceId, _id);
      expect(states, [
        DeviceLinkState.disconnected,
        DeviceLinkState.connecting,
        DeviceLinkState.connected,
      ]);
      // The link only lives while the plugin stream is listened to.
      expect(connection.hasListener, isTrue);
      expect(ppg.hasListener, isTrue);
      expect(status.hasListener, isTrue);

      final discovery =
          verify(
                () => client.connectToDevice(
                  id: _id,
                  servicesWithCharacteristicsToDiscover: captureAny(
                    named: 'servicesWithCharacteristicsToDiscover',
                  ),
                  connectionTimeout: const Duration(seconds: 10),
                ),
              ).captured.single
              as Map<Uuid, List<Uuid>>;
      expect(discovery[_service], containsAll([_ppg, _control, _status]));
    });

    test('is a no-op when already connected to the same id', () async {
      await connected(adapter);
      expect((await adapter.connect(_id)).isOk, isTrue);
      verify(
        () => client.connectToDevice(
          id: any(named: 'id'),
          servicesWithCharacteristicsToDiscover: any(
            named: 'servicesWithCharacteristicsToDiscover',
          ),
          connectionTimeout: any(named: 'connectionTimeout'),
        ),
      ).called(1);
    });

    test('passes notifications through as Uint8List', () async {
      await connected(adapter);
      final ppgEvents = <Uint8List>[];
      final statusEvents = <Uint8List>[];
      adapter.ppgNotifications.listen(ppgEvents.add);
      adapter.statusNotifications.listen(statusEvents.add);

      ppg.add([1, 2, 3]);
      status.add([9]);
      await pumpEventQueue();

      expect(ppgEvents.single, Uint8List.fromList([1, 2, 3]));
      expect(statusEvents.single, Uint8List.fromList([9]));
    });

    test('disconnect cancels the connection and notifications', () async {
      await connected(adapter);
      final states = <DeviceLinkState>[];
      adapter.linkState.listen(states.add);

      await adapter.disconnect();
      await pumpEventQueue();

      expect(connection.hasListener, isFalse);
      expect(ppg.hasListener, isFalse);
      expect(status.hasListener, isFalse);
      expect(adapter.connectedDeviceId, isNull);
      expect(states, [
        DeviceLinkState.connected,
        DeviceLinkState.disconnecting,
        DeviceLinkState.disconnected,
      ]);
      await adapter.disconnect(); // safe when already disconnected
    });

    test('unexpected link loss reports disconnected and cleans up', () async {
      await connected(adapter);
      connection.add(_update(DeviceConnectionState.disconnected));
      await pumpEventQueue();

      expect(adapter.currentLinkState, DeviceLinkState.disconnected);
      expect(connection.hasListener, isFalse);
      expect(ppg.hasListener, isFalse);
      expect(
        await adapter.writeControl(Uint8List(1)),
        isA<Err<void, Failure>>().having(
          (e) => e.failure,
          'failure',
          isA<ConnectionLost>(),
        ),
      );
    });

    test('failedToConnect maps to DeviceNotFound', () async {
      final future = adapter.connect(_id);
      await pumpEventQueue();
      connection.add(
        _update(
          DeviceConnectionState.disconnected,
          failure: const GenericFailure(
            code: ConnectionError.failedToConnect,
            message: 'GATT 133',
          ),
        ),
      );
      final result = await future;
      expect(result.failureOrNull, isA<DeviceNotFound>());
      expect(adapter.currentLinkState, DeviceLinkState.disconnected);
    });

    test('plugin TimeoutException maps to DeviceNotFound', () async {
      final future = adapter.connect(_id);
      await pumpEventQueue();
      connection.addError(TimeoutException('no answer'));
      expect((await future).failureOrNull, isA<DeviceNotFound>());
      expect(connection.hasListener, isFalse);
    });

    test('permission errors map to BlePermissionDenied', () async {
      final future = adapter.connect(_id);
      await pumpEventQueue();
      connection.addError(Exception('Missing BLUETOOTH_CONNECT permission'));
      expect((await future).failureOrNull, isA<BlePermissionDenied>());
    });

    test('local timeout fails a connect that never answers', () {
      fakeAsync((async) {
        Result<void, Failure>? result;
        adapter
            .connect(_id, timeout: const Duration(seconds: 3))
            .then((r) => result = r);
        async.elapse(const Duration(seconds: 2));
        expect(result, isNull);
        expect(adapter.currentLinkState, DeviceLinkState.connecting);
        async.elapse(const Duration(seconds: 2));
        expect(result?.failureOrNull, isA<DeviceNotFound>());
        expect(adapter.currentLinkState, DeviceLinkState.disconnected);
        expect(connection.hasListener, isFalse);
      });
    });

    test('disconnect during connect fails the pending connect', () async {
      final future = adapter.connect(_id);
      await pumpEventQueue();
      await adapter.disconnect();
      expect((await future).failureOrNull, isA<ConnectionLost>());
      expect(connection.hasListener, isFalse);
    });
  });

  group('GATT operations', () {
    test('fail with ConnectionLost while disconnected', () async {
      expect(
        (await adapter.requestMtu(247)).failureOrNull,
        isA<ConnectionLost>(),
      );
      expect((await adapter.readStatus()).failureOrNull, isA<ConnectionLost>());
      expect(
        (await adapter.writeControl(Uint8List(1))).failureOrNull,
        isA<ConnectionLost>(),
      );
    });

    test('requestMtu returns the negotiated value', () async {
      when(
        () => client.requestMtu(deviceId: _id, mtu: 247),
      ).thenAnswer((_) async => 185);
      await connected(adapter);
      expect((await adapter.requestMtu(247)).valueOrNull, 185);
    });

    test('readStatus reads the status characteristic', () async {
      when(
        () => client.readCharacteristic(_char(_status)),
      ).thenAnswer((_) async => [7, 8]);
      await connected(adapter);
      expect(
        (await adapter.readStatus()).valueOrNull,
        Uint8List.fromList([7, 8]),
      );
    });

    test(
      'writeControl writes the control characteristic with response',
      () async {
        when(
          () => client.writeCharacteristicWithResponse(
            any(),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});
        await connected(adapter);

        expect(
          (await adapter.writeControl(Uint8List.fromList([1, 2]))).isOk,
          isTrue,
        );
        verify(
          () => client.writeCharacteristicWithResponse(
            _char(_control),
            value: [1, 2],
          ),
        ).called(1);
      },
    );

    test('plugin errors map to Failures', () async {
      when(
        () => client.requestMtu(
          deviceId: any(named: 'deviceId'),
          mtu: any(named: 'mtu'),
        ),
      ).thenThrow(Exception('GATT error'));
      when(
        () => client.readCharacteristic(any()),
      ).thenThrow(Exception('Bluetooth is off'));
      when(
        () => client.writeCharacteristicWithResponse(
          any(),
          value: any(named: 'value'),
        ),
      ).thenThrow(Exception('permission denied'));
      await connected(adapter);

      expect(
        (await adapter.requestMtu(247)).failureOrNull,
        isA<ConnectionLost>(),
      );
      expect((await adapter.readStatus()).failureOrNull, isA<BluetoothOff>());
      expect(
        (await adapter.writeControl(Uint8List(1))).failureOrNull,
        isA<BlePermissionDenied>(),
      );
    });
  });

  group('iOS MAC resolution', () {
    test('Android connects to the MAC directly without scanning', () async {
      await connected(adapter);
      verifyNever(
        () => client.scanForDevices(
          withServices: any(named: 'withServices'),
          scanMode: any(named: 'scanMode'),
        ),
      );
    });

    test('iOS resolves a MAC via the advertised name suffix', () async {
      final ios = build(platform: TargetPlatform.iOS);
      final future = ios.connect(_id);
      await pumpEventQueue();
      scanResults
        ..add(_device('UUID-OTHER', name: 'PPG-1234'))
        ..add(_device('UUID-MINE', name: 'PPG-eeff'));
      await pumpEventQueue();
      connection.add(_update(DeviceConnectionState.connected));

      expect((await future).isOk, isTrue);
      expect(ios.connectedDeviceId, _id);
      verify(
        () => client.connectToDevice(
          id: 'UUID-MINE',
          servicesWithCharacteristicsToDiscover: any(
            named: 'servicesWithCharacteristicsToDiscover',
          ),
          connectionTimeout: any(named: 'connectionTimeout'),
        ),
      ).called(1);
      expect(scanResults.hasListener, isFalse);

      when(() => client.readCharacteristic(any())).thenAnswer((_) async => [1]);
      await ios.readStatus();
      verify(
        () => client.readCharacteristic(_char(_status, 'UUID-MINE')),
      ).called(1);
    });

    test('iOS uses the only PPG device in range', () {
      fakeAsync((async) {
        final ios = build(platform: TargetPlatform.iOS);
        Result<void, Failure>? result;
        ios.connect(_id).then((r) => result = r);
        async.flushMicrotasks();
        scanResults.add(_device('UUID-ONLY', name: 'Wearable'));
        async.elapse(const Duration(seconds: 2));
        connection.add(_update(DeviceConnectionState.connected));
        async.flushMicrotasks();
        expect(result?.isOk, isTrue);
        verify(
          () => client.connectToDevice(
            id: 'UUID-ONLY',
            servicesWithCharacteristicsToDiscover: any(
              named: 'servicesWithCharacteristicsToDiscover',
            ),
            connectionTimeout: any(named: 'connectionTimeout'),
          ),
        ).called(1);
      });
    });

    test('iOS fails with DeviceNotFound when ambiguous', () {
      fakeAsync((async) {
        final ios = build(platform: TargetPlatform.iOS);
        Result<void, Failure>? result;
        ios.connect(_id).then((r) => result = r);
        async.flushMicrotasks();
        scanResults
          ..add(_device('U1', name: 'A'))
          ..add(_device('U2', name: 'B'));
        async.elapse(const Duration(seconds: 2));
        expect(result?.failureOrNull, isA<DeviceNotFound>());
        expect(ios.currentLinkState, DeviceLinkState.disconnected);
      });
    });
  });
}
