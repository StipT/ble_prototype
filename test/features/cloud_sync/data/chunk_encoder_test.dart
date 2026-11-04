import 'dart:io';
import 'dart:typed_data';

import 'package:ble_prototype/core/database/app_database.dart';
import 'package:ble_prototype/core/database/sample_packing.dart';
import 'package:ble_prototype/features/cloud_sync/data/chunk_encoder.dart';
import 'package:ble_prototype/features/cloud_sync/data/firebase_cloud_remote.dart';
import 'package:ble_prototype/features/cloud_sync/domain/entities/cloud_documents.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/packets.dart';

final _session = SessionRow(
  id: 'sess',
  deviceId: 'fake-ppg-01',
  startedAt: DateTime.utc(2026),
  sampleRateHz: 50,
);

PacketRow _row(int seq) {
  final p = packet(seq);
  return PacketRow(
    sessionId: 'sess',
    sequence: seq,
    timestamp: p.timestamp,
    samples: SamplePacking.pack(p.samples),
    fromHistory: false,
  );
}

List<int> _decode(ChunkUpload c) =>
    SamplePacking.unpack(Uint8List.fromList(GZipCodec().decode(c.samples)));

void main() {
  group('ChunkEncoder', () {
    test('encodes a full chunk; gzip round-trips to all samples', () {
      final rows = [for (var s = 300; s < 400; s++) _row(s)].reversed.toList();
      final c = ChunkEncoder.encode(
        session: _session,
        chunkIndex: 3,
        packets: rows,
      );

      expect(c.docId, 'sess_3');
      expect(c.sessionId, 'sess');
      expect(c.firstSequence, 300);
      expect(c.lastSequence, 399);
      expect(c.packetCount, 100);
      expect(c.samplesPerPacket, 5);
      expect(c.missingSequences, isEmpty);
      expect(c.startedAt, packet(300).timestamp);
      expect(c.sampleRateHz, 50);
      expect(c.deviceId, 'fake-ppg-01');
      expect(c.encoding, 'gzip-u24le');
      expect(_decode(c), [
        for (var s = 300; s < 400; s++) ...packet(s).samples,
      ]);
      expect(c.samples.length, lessThan(1500), reason: 'compressed');
    });

    test('lists missing sequences inside first..last', () {
      final rows = [
        for (var s = 10; s <= 20; s++)
          if (s != 12 && s != 13 && s != 17) _row(s),
      ];
      final c = ChunkEncoder.encode(
        session: _session,
        chunkIndex: 0,
        packets: rows,
      );
      expect(c.firstSequence, 10);
      expect(c.lastSequence, 20);
      expect(c.packetCount, 8);
      expect(c.missingSequences, [12, 13, 17]);
      // Rules invariant: missing == span - packetCount.
      expect(
        c.missingSequences.length,
        c.lastSequence - c.firstSequence + 1 - c.packetCount,
      );
      expect(_decode(c).length, 8 * 5);
    });

    test('is deterministic (identical retry document)', () {
      final rows = [for (var s = 0; s < 50; s++) _row(s)];
      final a = ChunkEncoder.encode(
        session: _session,
        chunkIndex: 0,
        packets: rows,
      );
      final b = ChunkEncoder.encode(
        session: _session,
        chunkIndex: 0,
        packets: rows.reversed.toList(),
      );
      expect(a, b);
    });

    test('rejects empty, out-of-chunk, duplicate and ragged input', () {
      ChunkUpload enc(List<PacketRow> rows, [int index = 0]) =>
          ChunkEncoder.encode(
            session: _session,
            chunkIndex: index,
            packets: rows,
          );
      expect(() => enc([]), throwsArgumentError);
      expect(() => enc([_row(100)]), throwsArgumentError);
      expect(() => enc([_row(99)], 1), throwsArgumentError);
      expect(() => enc([_row(1), _row(1)]), throwsArgumentError);
      expect(
        () => enc([_row(1), _row(2).copyWith(samples: Uint8List(6))]),
        throwsArgumentError,
      );
    });
  });

  group('Firestore mapping', () {
    test('chunk fields match the rules (types and names)', () {
      final c = ChunkEncoder.encode(
        session: _session,
        chunkIndex: 0,
        packets: [_row(0), _row(2)],
      );
      final m = chunkToFirestore(c);
      expect(m.keys.toSet(), {
        'sessionId',
        'chunkIndex',
        'firstSequence',
        'lastSequence',
        'packetCount',
        'samplesPerPacket',
        'missingSequences',
        'startedAt',
        'sampleRateHz',
        'deviceId',
        'encoding',
        'samples',
      });
      expect(m['chunkIndex'], isA<int>());
      expect(m['missingSequences'], [1]);
      expect(m['startedAt'], Timestamp.fromDate(packet(0).timestamp));
      expect(m['samples'], isA<Blob>());
      expect((m['samples']! as Blob).bytes, c.samples);
      expect(m['encoding'], 'gzip-u24le');
    });

    test('session fields', () {
      final m = sessionToFirestore(
        SessionUpload(
          sessionId: 's',
          deviceId: 'd',
          startedAt: DateTime.utc(2026),
          sampleRateHz: 50,
        ),
      );
      expect(m, {
        'deviceId': 'd',
        'startedAt': Timestamp.fromDate(DateTime.utc(2026)),
        'endedAt': null,
        'sampleRateHz': 50,
      });
    });
  });
}
