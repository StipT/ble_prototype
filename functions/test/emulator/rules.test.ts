import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, setLogLevel, Timestamp, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

import { chunkId, clientChunk, requireEmulators } from "../fixtures";

// Separate project id so the chunk trigger (registered for demo-ppg) does not fire here.
const PROJECT_ID = "demo-ppg-rules";
const ALICE = "alice";
const BOB = "bob";
const SESSION = "session-a";

let env: RulesTestEnvironment;

const session = () => ({
  deviceId: "fake-ppg-01",
  startedAt: Timestamp.fromMillis(1_760_000_000_000),
  endedAt: null,
  sampleRateHz: 50,
});
const chunk = (index = 0, overrides: Record<string, unknown> = {}) => ({
  ...clientChunk({ sessionId: SESSION, chunkIndex: index, samples: Array(500).fill(8_000_000) }),
  ...overrides,
});

const db = (uid: string | null) =>
  uid === null ? env.unauthenticatedContext().firestore() : env.authenticatedContext(uid).firestore();
const chunkPath = (uid: string, index = 0) => `users/${uid}/sessions/${SESSION}/chunks/${chunkId(SESSION, index)}`;

beforeAll(async () => {
  requireEmulators("FIRESTORE_EMULATOR_HOST");
  // Denied writes are expected here; keep the SDK from logging each one.
  setLogLevel("silent");
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8") },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

describe("ownership", () => {
  it("lets a user create and read their own session", async () => {
    const ref = doc(db(ALICE), `users/${ALICE}/sessions/${SESSION}`);
    await assertSucceeds(setDoc(ref, session()));
    await assertSucceeds(getDoc(ref));
  });

  it("denies unauthenticated access", async () => {
    await assertFails(setDoc(doc(db(null), `users/${ALICE}/sessions/${SESSION}`), session()));
    await assertFails(getDoc(doc(db(null), `users/${ALICE}/sessions/${SESSION}`)));
  });

  it("denies cross-user reads and writes anywhere under users/{uid}/**", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${ALICE}`), { name: "Alice" });
      await setDoc(doc(ctx.firestore(), `users/${ALICE}/sessions/${SESSION}`), session());
      await setDoc(doc(ctx.firestore(), chunkPath(ALICE)), chunk());
      await setDoc(doc(ctx.firestore(), `users/${ALICE}/sessions/${SESSION}/metrics/${chunkId(SESSION, 0)}`), {
        status: "ok",
      });
    });
    const bob = db(BOB);
    await assertFails(getDoc(doc(bob, `users/${ALICE}`)));
    await assertFails(getDoc(doc(bob, `users/${ALICE}/sessions/${SESSION}`)));
    await assertFails(getDoc(doc(bob, chunkPath(ALICE))));
    await assertFails(getDoc(doc(bob, `users/${ALICE}/sessions/${SESSION}/metrics/${chunkId(SESSION, 0)}`)));
    await assertFails(setDoc(doc(bob, `users/${ALICE}`), { name: "Bob" }));
    await assertFails(setDoc(doc(bob, `users/${ALICE}/sessions/other`), session()));
    await assertFails(setDoc(doc(bob, chunkPath(ALICE, 1)), chunk(1)));
  });

  it("denies writes outside users/{uid}", async () => {
    await assertFails(setDoc(doc(db(ALICE), "global/x"), { a: 1 }));
  });

  it("lets the owner read function-written metrics but not write them", async () => {
    const path = `users/${ALICE}/sessions/${SESSION}/metrics/${chunkId(SESSION, 0)}`;
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), { status: "ok" }));
    await assertSucceeds(getDoc(doc(db(ALICE), path)));
    await assertFails(setDoc(doc(db(ALICE), path), { status: "forged" }));
  });
});

describe("sessions", () => {
  it("allows ending a session", async () => {
    const ref = doc(db(ALICE), `users/${ALICE}/sessions/${SESSION}`);
    await setDoc(ref, session());
    await assertSucceeds(updateDoc(ref, { endedAt: Timestamp.now() }));
  });

  it("rejects malformed sessions and deletes", async () => {
    const ref = doc(db(ALICE), `users/${ALICE}/sessions/${SESSION}`);
    await assertFails(setDoc(ref, { ...session(), sampleRateHz: "50" }));
    await assertFails(setDoc(ref, { ...session(), extra: true }));
    await setDoc(ref, session());
    await assertFails(deleteDoc(ref));
  });
});

describe("chunks are append-only", () => {
  it("allows creating a valid chunk", async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), chunkPath(ALICE)), chunk()));
  });

  it("allows an idempotent retry that rewrites the identical document", async () => {
    const ref = doc(db(ALICE), chunkPath(ALICE));
    const data = chunk();
    await setDoc(ref, data);
    await assertSucceeds(setDoc(ref, data));
  });

  it("denies changing or deleting an uploaded chunk", async () => {
    const ref = doc(db(ALICE), chunkPath(ALICE));
    await setDoc(ref, chunk());
    await assertFails(setDoc(ref, chunk(0, { deviceId: "other" })));
    await assertFails(updateDoc(ref, { packetCount: 50 }));
    await assertFails(deleteDoc(ref));
  });

  it("accepts a partial chunk with missing packets", async () => {
    const data = clientChunk({
      sessionId: SESSION,
      chunkIndex: 2,
      samples: Array(485).fill(8_000_000),
      firstSequence: 200,
      lastSequence: 299,
      packetCount: 97,
      missingSequences: [210, 211, 250],
    });
    await assertSucceeds(setDoc(doc(db(ALICE), chunkPath(ALICE, 2)), data));
  });

  it.each([
    ["doc id not sessionId_chunkIndex", 0, { chunkIndex: 1, firstSequence: 100, lastSequence: 199 }],
    ["sessionId not matching path", 0, { sessionId: "other" }],
    ["sequence outside chunk", 0, { lastSequence: 100 }],
    ["packetCount exceeding span", 0, { packetCount: 101 }],
    ["missingSequences inconsistent", 0, { missingSequences: [5] }],
    ["wrong encoding", 0, { encoding: "raw" }],
    ["samples not bytes", 0, { samples: "AAAA" }],
    ["string sampleRateHz", 0, { sampleRateHz: "50" }],
    ["unknown field", 0, { uploadedBy: "me" }],
  ] as const)("rejects chunk with %s", async (_name, index, overrides) => {
    await assertFails(setDoc(doc(db(ALICE), chunkPath(ALICE, index)), chunk(index, overrides)));
  });

  it("rejects chunks with missing fields", async () => {
    const { deviceId: _ignored, ...withoutDevice } = chunk();
    await assertFails(setDoc(doc(db(ALICE), chunkPath(ALICE)), withoutDevice));
  });
});
