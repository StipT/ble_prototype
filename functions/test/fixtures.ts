import { Bytes, Timestamp } from "firebase/firestore";

import { encodeSamples } from "../src/chunk";

/** Chunk document exactly as the Flutter client uploads it (client SDK types). */
export function clientChunk(opts: {
  sessionId: string;
  chunkIndex: number;
  samples: number[];
  firstSequence?: number;
  lastSequence?: number;
  packetCount?: number;
  missingSequences?: number[];
}) {
  const first = opts.firstSequence ?? opts.chunkIndex * 100;
  const packetCount = opts.packetCount ?? opts.samples.length / 5;
  return {
    sessionId: opts.sessionId,
    chunkIndex: opts.chunkIndex,
    firstSequence: first,
    lastSequence: opts.lastSequence ?? first + packetCount - 1,
    packetCount,
    samplesPerPacket: 5,
    missingSequences: opts.missingSequences ?? [],
    startedAt: Timestamp.fromMillis(1_760_000_000_000),
    sampleRateHz: 50,
    deviceId: "fake-ppg-01",
    encoding: "gzip-u24le",
    samples: Bytes.fromUint8Array(encodeSamples(opts.samples)),
  };
}

export function chunkId(sessionId: string, chunkIndex: number): string {
  return `${sessionId}_${chunkIndex}`;
}

/** Fails fast with a clear message when the suite is run without emulators. */
export function requireEmulators(...vars: string[]): void {
  const missing = vars.filter((v) => !process.env[v]);
  if (missing.length > 0) {
    throw new Error(
      `${missing.join(", ")} not set. Run via "npm run test:emulators" (firebase emulators:exec).`,
    );
  }
}
