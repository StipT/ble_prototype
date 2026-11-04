import { gunzipSync, gzipSync } from "node:zlib";

/** Value of the chunk doc `encoding` field: gzip over packed unsigned 24-bit LE samples. */
export const CHUNK_ENCODING = "gzip-u24le";

/** Packets per chunk on the client (`AppDatabase.packetsPerChunk`). */
export const PACKETS_PER_CHUNK = 100;

/**
 * Client-written chunk document at
 * `users/{uid}/sessions/{sessionId}/chunks/{sessionId}_{chunkIndex}`.
 * Field types are what Firestore stores; `samples` is a Bytes value.
 */
export interface ChunkDoc {
  sessionId: string;
  chunkIndex: number;
  firstSequence: number;
  lastSequence: number;
  packetCount: number;
  samplesPerPacket: number;
  /** Sequences in [firstSequence, lastSequence] that are absent, ascending. */
  missingSequences: number[];
  sampleRateHz: number;
  deviceId: string;
  encoding: string;
  /** Raw gzip bytes. */
  samples: Uint8Array;
}

/** A run of consecutive packets, i.e. samples without a time gap. */
export interface Segment {
  /** Index of the first sample in the decoded sample array. */
  offset: number;
  length: number;
}

/** Decoded chunk ready for analysis. */
export interface DecodedChunk {
  samples: number[];
  segments: Segment[];
  /** Number of samples the chunk would contain without missing packets. */
  expectedSampleCount: number;
}

export class ChunkFormatError extends Error {}

/** Packs unsigned 24-bit samples little-endian (mirror of the Dart `SamplePacking.pack`). */
export function packSamples(samples: readonly number[]): Uint8Array {
  const out = new Uint8Array(samples.length * 3);
  samples.forEach((s, i) => {
    out[i * 3] = s & 0xff;
    out[i * 3 + 1] = (s >> 8) & 0xff;
    out[i * 3 + 2] = (s >> 16) & 0xff;
  });
  return out;
}

/** Inverse of [packSamples]. */
export function unpackSamples(bytes: Uint8Array): number[] {
  if (bytes.length % 3 !== 0) {
    throw new ChunkFormatError(`sample payload length ${bytes.length} is not a multiple of 3`);
  }
  const out = new Array<number>(bytes.length / 3);
  for (let i = 0; i < out.length; i++) {
    out[i] = bytes[i * 3] | (bytes[i * 3 + 1] << 8) | (bytes[i * 3 + 2] << 16);
  }
  return out;
}

/** gzip(pack(samples)) — what the client stores in `samples`. */
export function encodeSamples(samples: readonly number[]): Uint8Array {
  return new Uint8Array(gzipSync(packSamples(samples)));
}

/**
 * Validates [doc] beyond what the security rules can check (payload size vs.
 * packet count, missing-sequence list) and decodes the samples into
 * gap-free segments.
 */
export function decodeChunk(doc: ChunkDoc): DecodedChunk {
  if (doc.encoding !== CHUNK_ENCODING) {
    throw new ChunkFormatError(`unsupported encoding ${doc.encoding}`);
  }
  let raw: Uint8Array;
  try {
    raw = gunzipSync(doc.samples);
  } catch (e) {
    throw new ChunkFormatError(`samples are not valid gzip: ${(e as Error).message}`);
  }
  const samples = unpackSamples(raw);
  const spp = doc.samplesPerPacket;
  if (samples.length !== doc.packetCount * spp) {
    throw new ChunkFormatError(
      `expected ${doc.packetCount * spp} samples (${doc.packetCount} packets x ${spp}), got ${samples.length}`,
    );
  }

  const span = doc.lastSequence - doc.firstSequence + 1;
  const missing = new Set(doc.missingSequences);
  if (missing.size !== doc.missingSequences.length || span - missing.size !== doc.packetCount) {
    throw new ChunkFormatError("missingSequences does not match packetCount");
  }
  for (const seq of missing) {
    if (!Number.isInteger(seq) || seq <= doc.firstSequence || seq >= doc.lastSequence) {
      throw new ChunkFormatError(`missing sequence ${seq} outside (firstSequence, lastSequence)`);
    }
  }

  const segments: Segment[] = [];
  let offset = 0;
  let current: Segment | null = null;
  for (let seq = doc.firstSequence; seq <= doc.lastSequence; seq++) {
    if (missing.has(seq)) {
      current = null;
      continue;
    }
    if (current === null) {
      current = { offset, length: 0 };
      segments.push(current);
    }
    current.length += spp;
    offset += spp;
  }

  return { samples, segments, expectedSampleCount: span * spp };
}
