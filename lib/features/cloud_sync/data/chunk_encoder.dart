import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import '../../../core/database/app_database.dart';
import '../domain/entities/cloud_documents.dart';

/// Builds the Firestore chunk document from the locally stored packets.
///
/// Encoding (`gzip-u24le`, see `functions/README.md`): the packets' samples
/// are concatenated in ascending sequence order — each packet row already
/// stores them packed as unsigned 24-bit little-endian, so concatenating
/// the blobs *is* `SamplePacking.pack(allSamples)` — and the result is
/// gzip-compressed. A 100-packet chunk is 1500 bytes raw.
///
/// The output is deterministic for the same packets, which matters: the
/// rules only allow re-writing a chunk document with identical content, so
/// a retry after a crash must produce the same bytes.
abstract final class ChunkEncoder {
  /// Encodes [packets] (all of chunk [chunkIndex] of [session], any order)
  /// into an upload. Throws [ArgumentError] when the packets are empty,
  /// outside the chunk, duplicated, or have differing sample counts.
  static ChunkUpload encode({
    required SessionRow session,
    required int chunkIndex,
    required List<PacketRow> packets,
  }) {
    if (packets.isEmpty) {
      throw ArgumentError.value(packets, 'packets', 'chunk has no packets');
    }
    final sorted = [...packets]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    const perChunk = AppDatabase.packetsPerChunk;
    final first = sorted.first.sequence;
    final last = sorted.last.sequence;
    if (first < chunkIndex * perChunk || last >= (chunkIndex + 1) * perChunk) {
      throw ArgumentError('packets $first..$last outside chunk $chunkIndex');
    }

    final bytesPerPacket = sorted.first.samples.length;
    if (bytesPerPacket == 0 || bytesPerPacket % 3 != 0) {
      throw ArgumentError('invalid packed sample length $bytesPerPacket');
    }
    final packed = BytesBuilder(copy: false);
    final missing = <int>[];
    int? previous;
    for (final p in sorted) {
      if (p.sequence == previous) {
        throw ArgumentError('duplicate sequence ${p.sequence}');
      }
      if (p.samples.length != bytesPerPacket) {
        throw ArgumentError('packet ${p.sequence} has a different length');
      }
      if (previous != null) {
        for (var s = previous + 1; s < p.sequence; s++) {
          missing.add(s);
        }
      }
      packed.add(p.samples);
      previous = p.sequence;
    }

    return ChunkUpload(
      sessionId: session.id,
      chunkIndex: chunkIndex,
      firstSequence: first,
      lastSequence: last,
      packetCount: sorted.length,
      samplesPerPacket: bytesPerPacket ~/ 3,
      missingSequences: List.unmodifiable(missing),
      startedAt: sorted.first.timestamp,
      sampleRateHz: session.sampleRateHz,
      deviceId: session.deviceId,
      samples: Uint8List.fromList(GZipCodec().encode(packed.takeBytes())),
    );
  }
}
