import { deleteApp, FirebaseApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import {
  connectFirestoreEmulator,
  doc,
  DocumentData,
  Firestore,
  getFirestore,
  onSnapshot,
  setDoc,
} from "firebase/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { beatSignal, fakeDeviceSignal } from "../synth";
import { chunkId, clientChunk, requireEmulators } from "../fixtures";

// Must match .firebaserc / emulators:exec --project: the trigger only fires for this project.
const PROJECT_ID = "demo-ppg";

let app: FirebaseApp;
let db: Firestore;
let uid: string;

/** Resolves with the metrics doc once the function has written it. */
function waitForMetrics(sessionId: string, index: number, timeoutMs = 20_000): Promise<DocumentData> {
  const ref = doc(db, `users/${uid}/sessions/${sessionId}/metrics/${chunkId(sessionId, index)}`);
  return new Promise((resolvePromise, reject) => {
    const timer = setTimeout(() => {
      unsubscribe();
      reject(new Error(`metrics for ${ref.path} not written within ${timeoutMs} ms`));
    }, timeoutMs);
    const unsubscribe = onSnapshot(ref, (snap) => {
      if (!snap.exists()) return;
      clearTimeout(timer);
      unsubscribe();
      resolvePromise(snap.data());
    }, reject);
  });
}

async function upload(sessionId: string, index: number, data: ReturnType<typeof clientChunk>) {
  await setDoc(doc(db, `users/${uid}/sessions/${sessionId}/chunks/${chunkId(sessionId, index)}`), data);
}

beforeAll(async () => {
  requireEmulators("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST");
  app = initializeApp({ projectId: PROJECT_ID, apiKey: "demo-key" }, `trigger-test-${Date.now()}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST!.split(":");
  db = getFirestore(app);
  connectFirestoreEmulator(db, host, Number(port));
  uid = (await signInAnonymously(auth)).user.uid;
});

afterAll(async () => {
  if (app) await deleteApp(app);
});

describe("analyzeChunkOnCreate (emulator)", () => {
  it("computes HR, HRV and signal quality for an uploaded chunk", async () => {
    const sessionId = `s-${Date.now()}`;
    await setDoc(doc(db, `users/${uid}/sessions/${sessionId}`), {
      deviceId: "fake-ppg-01",
      startedAt: clientChunk({ sessionId, chunkIndex: 0, samples: [] }).startedAt,
      sampleRateHz: 50,
    });
    await upload(sessionId, 7, clientChunk({ sessionId, chunkIndex: 7, samples: fakeDeviceSignal({ seconds: 10, heartRateBpm: 72 }) }));

    const m = await waitForMetrics(sessionId, 7);
    expect(m.status).toBe("ok");
    expect(m.chunkId).toBe(chunkId(sessionId, 7));
    expect(m.chunkIndex).toBe(7);
    expect(m.firstSequence).toBe(700);
    expect(m.lastSequence).toBe(799);
    expect(Math.abs(m.avgHeartRateBpm - 72)).toBeLessThan(2);
    expect(m.hrvRmssdMs).toBeTypeOf("number");
    expect(m.signalQuality.label).toBe("good");
    expect(m.algorithmVersion).toBe(1);
    expect(m.computedAt).toBeDefined();
  });

  it("measures HRV across a chunk with a missing packet", async () => {
    const sessionId = `s-hrv-${Date.now()}`;
    const ibis = Array.from({ length: 12 }, (_, i) => (i % 2 === 0 ? 760 : 860));
    const signal = beatSignal({ ibisMs: ibis }).slice(0, 500);
    // Packet 340 (samples 200..204) never arrived.
    const samples = [...signal.slice(0, 200), ...signal.slice(205)];
    await upload(
      sessionId,
      3,
      clientChunk({
        sessionId,
        chunkIndex: 3,
        samples,
        firstSequence: 300,
        lastSequence: 399,
        packetCount: 99,
        missingSequences: [340],
      }),
    );

    const m = await waitForMetrics(sessionId, 3);
    expect(m.status).toBe("ok");
    expect(m.avgHeartRateBpm).toBeGreaterThan(70);
    expect(m.avgHeartRateBpm).toBeLessThan(78);
    expect(Math.abs(m.hrvRmssdMs - 100)).toBeLessThan(15);
    expect(m.signalQuality.coverage).toBe(0.99);
  });

  it("flags a chunk whose payload does not decode as invalid", async () => {
    const sessionId = `s-bad-${Date.now()}`;
    const data = clientChunk({ sessionId, chunkIndex: 0, samples: Array(500).fill(1) });
    await upload(sessionId, 0, { ...data, packetCount: 50, lastSequence: 49 });

    const m = await waitForMetrics(sessionId, 0);
    expect(m.status).toBe("invalid");
    expect(m.error).toMatch(/expected 250 samples/);
    expect(m.avgHeartRateBpm).toBeUndefined();
  });
});
