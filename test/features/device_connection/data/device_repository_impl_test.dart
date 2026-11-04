import 'dart:async';
import 'dart:math' as math;

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/device_connection/data/device_repository_impl.dart';
import 'package:ble_prototype/features/device_connection/data/fake/fake_ppg_device.dart';
import 'package:ble_prototype/features/device_connection/data/fake/ppg_signal_generator.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ble_types.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakePpgDevice device;
  late DeviceRepositoryImpl repo;

  void setUpDevice({int backlog = 3000}) {
    device = FakePpgDevice(
      random: math.Random(1),
      generator: PpgSignalGenerator(random: math.Random(2)),
      backlogCapacity: backlog,
    );
    repo = DeviceRepositoryImpl(adapter: device);
  }

  /// Runs [body] in fake time; flushes timers so nothing leaks.
  void run(void Function(FakeAsync async) body, {int backlog = 3000}) {
    fakeAsync((async) {
      setUpDevice(backlog: backlog);
      body(async);
      device.dispose();
      async.flushMicrotasks();
    });
  }

  Result<T, Failure> await_<T>(
    FakeAsync async,
    Future<Result<T, Failure>> f, [
    Duration step = const Duration(seconds: 2),
  ]) {
    Result<T, Failure>? out;
    f.then((r) => out = r);
    async.elapse(step);
    return out!;
  }

  void connectAndStream(FakeAsync async) {
    expect(
      await_(async, repo.connect(FakePpgDevice.defaultDeviceId)).isOk,
      isTrue,
    );
    expect(await_(async, repo.startStreaming()).isOk, isTrue);
  }

  test('scan finds the fake device, de-duplicated', () {
    run((async) {
      final r = await_(
        async,
        repo.scan(timeout: const Duration(seconds: 3)),
        const Duration(seconds: 4),
      );
      expect(r.valueOrNull!.map((d) => d.id), [FakePpgDevice.defaultDeviceId]);
    });
  });

  test('scan with Bluetooth off fails with BluetoothOff', () {
    run((async) {
      device.bluetoothEnabled = false;
      final r = await_(async, repo.scan());
      expect(r.failureOrNull, isA<BluetoothOff>());
    });
  });

  test('connect negotiates MTU so 29-byte frames fit', () {
    run((async) {
      expect(
        await_(async, repo.connect(FakePpgDevice.defaultDeviceId)).isOk,
        isTrue,
      );
      expect(device.mtu, 247);
      expect(repo.currentLinkState, DeviceLinkState.connected);
    });
  });

  test('connect to an absent device fails with DeviceNotFound', () {
    run((async) {
      device.simulateOutage(const Duration(minutes: 1));
      final r = await_(async, repo.connect(FakePpgDevice.defaultDeviceId));
      expect(r.failureOrNull, isA<DeviceNotFound>());
    });
  });

  test('live packets arrive with consecutive sequence numbers', () {
    run((async) {
      final packets = <PpgPacket>[];
      repo.livePackets.listen(packets.add);
      connectAndStream(async);
      packets.clear();
      async.elapse(const Duration(seconds: 1));
      expect(packets.length, inInclusiveRange(9, 11));
      for (var i = 1; i < packets.length; i++) {
        expect(packets[i].sequence, packets[i - 1].sequence + 1);
      }
      expect(packets.every((p) => p.kind == PpgPacketKind.live), isTrue);
      expect(packets.first.samples, hasLength(5));
    });
  });

  test('skipping MTU negotiation truncates frames -> ProtocolError', () {
    run((async) {
      final packets = <PpgPacket>[];
      final errors = <ProtocolError>[];
      repo.livePackets.listen(packets.add);
      repo.protocolErrors.listen(errors.add);
      await_(async, device.connect(FakePpgDevice.defaultDeviceId));
      await_(async, repo.startStreaming());
      async.elapse(const Duration(seconds: 1));
      expect(packets, isEmpty);
      expect(errors, isNotEmpty);
    });
  });

  test('dropped packets show up as a sequence gap', () {
    run((async) {
      final packets = <PpgPacket>[];
      repo.livePackets.listen(packets.add);
      connectAndStream(async);
      async.elapse(const Duration(milliseconds: 500));
      device.dropNextPackets(3);
      async.elapse(const Duration(milliseconds: 1000));
      final seqs = packets.map((p) => p.sequence).toList();
      final gaps = [
        for (var i = 1; i < seqs.length; i++) seqs[i] - seqs[i - 1] - 1,
      ].where((g) => g > 0);
      expect(gaps, [3]);
    });
  });

  test('downloadHistory replays exactly the requested range', () {
    run((async) {
      async.elapse(const Duration(seconds: 3)); // ~30 packets in backlog
      connectAndStream(async);
      final got = <PpgPacket>[];
      var done = false;
      repo.downloadHistory(5, 14).listen(got.add, onDone: () => done = true);
      async.elapse(const Duration(milliseconds: 100));
      expect(done, isTrue);
      expect(got.map((p) => p.sequence), List.generate(10, (i) => 5 + i));
      expect(got.every((p) => p.kind == PpgPacketKind.history), isTrue);
    });
  });

  test('downloadHistory errors with ConnectionLost on link drop', () {
    run((async) {
      async.elapse(const Duration(seconds: 30)); // ~300 packets
      connectAndStream(async);
      final got = <PpgPacket>[];
      Object? error;
      repo
          .downloadHistory(0, 299)
          .listen(got.add, onError: (Object e) => error = e);
      async.flushMicrotasks();
      device.simulateDisconnect();
      async.elapse(const Duration(milliseconds: 100));
      expect(error, isA<ConnectionLost>());
      expect(got.length, lessThan(300));
    });
  });

  test('device backlog is a bounded ring buffer', () {
    run((async) {
      async.elapse(const Duration(seconds: 10)); // 100 packets
      expect(device.backlogLength, 50);
      expect(device.status.oldestSequence, device.status.latestSequence - 49);
    }, backlog: 50);
  });

  test('random disconnects drop the link', () {
    run((async) {
      connectAndStream(async);
      device.randomDisconnectsPerMinute = 600; // ~1 per tick
      async.elapse(const Duration(seconds: 2));
      expect(device.currentLinkState, DeviceLinkState.disconnected);
    });
  });

  test('status read reports battery and stored range', () {
    run((async) {
      async.elapse(const Duration(seconds: 1));
      connectAndStream(async);
      final s = await_(async, repo.readStatus()).valueOrNull!;
      expect(s.batteryPercent, inInclusiveRange(99, 100));
      expect(s.isStreaming, isTrue);
      expect(s.hasData, isTrue);
      expect(s.latestSequence, greaterThan(s.oldestSequence));
    });
  });

  test('commands fail with ConnectionLost when disconnected', () {
    run((async) {
      final r = await_(async, repo.startStreaming());
      expect(r.failureOrNull, isA<ConnectionLost>());
      final events = <Object>[];
      runZonedGuarded(() {
        repo.downloadHistory(0, 1).listen((_) {}, onError: events.add);
      }, (e, _) => events.add(e));
      async.elapse(const Duration(seconds: 1));
      expect(events.single, isA<ConnectionLost>());
    });
  });
}
