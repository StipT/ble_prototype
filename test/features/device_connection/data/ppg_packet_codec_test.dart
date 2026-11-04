import 'dart:typed_data';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/device_connection/data/protocol/ppg_packet_codec.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/device_status.dart';
import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = PpgPacketCodec();
  final ts = DateTime.fromMillisecondsSinceEpoch(1761300000123);

  PpgPacket packet({
    int seq = 42,
    List<int> samples = const [0, 1, 0x123456, 0xFFFFFF, 8000000],
    PpgPacketKind kind = PpgPacketKind.live,
  }) => PpgPacket(sequence: seq, timestamp: ts, samples: samples, kind: kind);

  group('data frames', () {
    test('round-trips live and history packets', () {
      for (final kind in PpgPacketKind.values) {
        final p = packet(kind: kind);
        final decoded = codec.decodeFrame(codec.encodePacket(p));
        expect(decoded, Ok<PpgFrame, ProtocolError>(PpgDataFrame(p)));
      }
    });

    test('round-trips max sequence and max sample count', () {
      final p = packet(
        seq: 0xFFFFFFFF,
        samples: List.filled(PpgPacketCodec.maxSamplesPerPacket, 0xABCDEF),
      );
      final bytes = codec.encodePacket(p);
      expect(bytes.length, lessThanOrEqualTo(PpgPacketCodec.maxFrameBytes));
      expect(codec.decodeFrame(bytes).valueOrNull, PpgDataFrame(p));
    });

    test('is little-endian on the wire', () {
      final bytes = codec.encodePacket(
        packet(seq: 0x01020304, samples: const [0x0A0B0C]),
      );
      expect(bytes[0], PpgPacketCodec.typeLive);
      expect(bytes.sublist(1, 5), [0x04, 0x03, 0x02, 0x01]);
      expect(bytes[13], 1);
      expect(bytes.sublist(14), [0x0C, 0x0B, 0x0A]);
    });

    test('5-sample frame does not fit the default 20-byte payload', () {
      final bytes = codec.encodePacket(packet());
      expect(bytes.length, 29);
      expect(bytes.length, greaterThan(23 - PpgPacketCodec.attHeaderBytes));
    });

    test('encoder rejects out-of-range values', () {
      expect(
        () => codec.encodePacket(packet(samples: const [0x1000000])),
        throwsArgumentError,
      );
      expect(
        () => codec.encodePacket(packet(samples: const [])),
        throwsArgumentError,
      );
      expect(() => codec.encodePacket(packet(seq: -1)), throwsArgumentError);
    });
  });

  group('history end frame', () {
    test('round-trips', () {
      const frame = HistoryEndFrame(
        fromSequence: 10,
        toSequence: 99,
        sentCount: 90,
      );
      expect(
        codec.decodeFrame(codec.encodeHistoryEnd(frame)).valueOrNull,
        frame,
      );
    });
  });

  group('malformed corpus yields ProtocolError', () {
    final valid = codec.encodePacket(packet());
    final corpus = <String, List<int>>{
      'empty': const [],
      'type byte only': const [PpgPacketCodec.typeLive],
      'truncated header': valid.sublist(0, 10),
      'header without samples': valid.sublist(
        0,
        PpgPacketCodec.dataHeaderBytes,
      ),
      'truncated sample (MTU cut)': valid.sublist(0, 20),
      'one extra byte': [...valid, 0],
      'count says 0': (Uint8List.fromList(valid)..[13] = 0),
      'count larger than payload': (Uint8List.fromList(valid)..[13] = 6),
      'count above max': (Uint8List.fromList(valid)
        ..[13] = PpgPacketCodec.maxSamplesPerPacket + 1),
      'oversize': List.filled(PpgPacketCodec.maxFrameBytes + 1, 0x01),
      'unknown type': (Uint8List.fromList(valid)..[0] = 0x7F),
      'history end too short': const [PpgPacketCodec.typeHistoryEnd, 1, 2],
      'history end too long': List.filled(14, PpgPacketCodec.typeHistoryEnd),
    };
    corpus.forEach((name, bytes) {
      test(name, () {
        final result = codec.decodeFrame(bytes);
        expect(result.failureOrNull, isA<ProtocolError>(), reason: '$result');
      });
    });

    test('accepts plain List<int> as well as Uint8List', () {
      expect(codec.decodeFrame(valid.toList()).isOk, isTrue);
    });
  });

  group('control commands', () {
    final commands = <ControlCommand>[
      const StartStreamingCommand(),
      const StopStreamingCommand(),
      SyncClockCommand(ts),
      const RequestHistoryCommand(5, 0xFFFFFFFF),
    ];
    for (final c in commands) {
      test('round-trips ${c.runtimeType}', () {
        expect(codec.decodeCommand(codec.encodeCommand(c)).valueOrNull, c);
      });
    }

    test('rejects malformed commands', () {
      for (final bad in [
        <int>[],
        [0x01, 0x00],
        [0x03, 1, 2],
        [0x09],
        codec.encodeCommand(const RequestHistoryCommand(9, 9)).sublist(0, 5),
      ]) {
        expect(codec.decodeCommand(bad).failureOrNull, isA<ProtocolError>());
      }
    });

    test('rejects inverted history range', () {
      final bytes =
          (ByteData(9)
                ..setUint8(0, 0x04)
                ..setUint32(1, 10, Endian.little)
                ..setUint32(5, 3, Endian.little))
              .buffer
              .asUint8List();
      expect(codec.decodeCommand(bytes).failureOrNull, isA<ProtocolError>());
    });
  });

  group('status', () {
    const status = DeviceStatus(
      batteryPercent: 87,
      isStreaming: true,
      isCharging: false,
      hasData: true,
      oldestSequence: 100,
      latestSequence: 4000000000,
    );

    test('round-trips', () {
      expect(
        codec.decodeStatus(codec.encodeStatus(status)).valueOrNull,
        status,
      );
    });

    test('rejects bad length and battery > 100', () {
      expect(
        codec.decodeStatus(const [1, 2, 3]).failureOrNull,
        isA<ProtocolError>(),
      );
      final bytes = codec.encodeStatus(status)..[0] = 101;
      expect(codec.decodeStatus(bytes).failureOrNull, isA<ProtocolError>());
    });
  });
}
