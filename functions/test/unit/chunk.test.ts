import { gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";

import {
  ChunkDoc,
  ChunkFormatError,
  decodeChunk,
  encodeSamples,
  packSamples,
  unpackSamples,
} from "../../src/chunk";

function chunkDoc(overrides: Partial<ChunkDoc> = {}, samples?: number[]): ChunkDoc {
  const packetCount = overrides.packetCount ?? 100;
  const spp = overrides.samplesPerPacket ?? 5;
  const values = samples ?? Array.from({ length: packetCount * spp }, (_, i) => i);
  return {
    sessionId: "s1",
    chunkIndex: 3,
    firstSequence: 300,
    lastSequence: 399,
    packetCount,
    samplesPerPacket: spp,
    missingSequences: [],
    sampleRateHz: 50,
    deviceId: "dev",
    encoding: "gzip-u24le",
    samples: encodeSamples(values),
    ...overrides,
  };
}

describe("sample packing", () => {
  it("packs 24-bit little-endian exactly like the Dart SamplePacking", () => {
    expect([...packSamples([0x123456, 0, 0xffffff])]).toEqual([0x56, 0x34, 0x12, 0, 0, 0, 0xff, 0xff, 0xff]);
  });

  it("round-trips", () => {
    const values = [0, 1, 8_000_000, 0xffffff, 42];
    expect(unpackSamples(packSamples(values))).toEqual(values);
  });

  it("rejects payloads that are not a multiple of 3 bytes", () => {
    expect(() => unpackSamples(new Uint8Array(4))).toThrow(ChunkFormatError);
  });
});

describe("decodeChunk", () => {
  it("decodes a full chunk as one segment", () => {
    const decoded = decodeChunk(chunkDoc());
    expect(decoded.samples).toHaveLength(500);
    expect(decoded.samples[499]).toBe(499);
    expect(decoded.segments).toEqual([{ offset: 0, length: 500 }]);
    expect(decoded.expectedSampleCount).toBe(500);
  });

  it("splits segments at missing packets", () => {
    const decoded = decodeChunk(
      chunkDoc({ packetCount: 97, missingSequences: [310, 311, 350] }),
    );
    expect(decoded.segments).toEqual([
      { offset: 0, length: 50 },
      { offset: 50, length: 190 },
      { offset: 240, length: 245 },
    ]);
    expect(decoded.expectedSampleCount).toBe(500);
  });

  it("supports partial chunks at session end", () => {
    const decoded = decodeChunk(chunkDoc({ lastSequence: 319, packetCount: 20 }));
    expect(decoded.segments).toEqual([{ offset: 0, length: 100 }]);
  });

  it.each([
    ["wrong encoding", { encoding: "raw" }],
    ["sample count mismatch", { packetCount: 99, missingSequences: [350] }, Array(500).fill(1)],
    ["missing list inconsistent", { packetCount: 99, missingSequences: [] }],
    ["missing outside range", { packetCount: 99, missingSequences: [400] }],
    ["duplicate missing", { packetCount: 98, missingSequences: [350, 350] }],
  ] as const)("rejects %s", (_name, overrides, samples?: readonly number[]) => {
    expect(() => decodeChunk(chunkDoc(overrides as Partial<ChunkDoc>, samples ? [...samples] : undefined))).toThrow(
      ChunkFormatError,
    );
  });

  it("rejects non-gzip payloads", () => {
    expect(() => decodeChunk(chunkDoc({ samples: packSamples([1, 2, 3]) }))).toThrow(/gzip/);
  });

  it("accepts gzip produced by any encoder (e.g. Dart's GZipCodec)", () => {
    const decoded = decodeChunk(
      chunkDoc({ packetCount: 1, lastSequence: 300 }, undefined),
    );
    expect(decoded.samples).toHaveLength(5);
    const viaNode = decodeChunk(
      chunkDoc({ packetCount: 1, lastSequence: 300, samples: gzipSync(packSamples([9, 8, 7, 6, 5]), { level: 9 }) }),
    );
    expect(viaNode.samples).toEqual([9, 8, 7, 6, 5]);
  });
});
