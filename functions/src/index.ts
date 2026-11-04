import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import { ALGORITHM_VERSION, analyzeChunk } from "./analysis";
import { ChunkDoc, ChunkFormatError, decodeChunk } from "./chunk";

initializeApp();
setGlobalOptions({ maxInstances: 10 });

/** Path of the client-written chunk documents. */
export const CHUNK_PATH = "users/{uid}/sessions/{sessionId}/chunks/{chunkId}";

/**
 * Runs once per newly created chunk: decodes the samples, computes avg HR,
 * HRV and signal quality, and writes them to
 * `users/{uid}/sessions/{sessionId}/metrics/{chunkId}`.
 *
 * The chunk itself is append-only, so results go to a sibling document that
 * only this function can write. The write is a deterministic `set`, so an
 * at-least-once redelivery of the event is harmless.
 */
export const analyzeChunkOnCreate = onDocumentCreated(CHUNK_PATH, async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const { uid, sessionId, chunkId } = event.params;
  const metricsRef = getFirestore().doc(`users/${uid}/sessions/${sessionId}/metrics/${chunkId}`);
  const doc = snapshot.data() as ChunkDoc;
  const base = {
    sessionId,
    chunkId,
    chunkIndex: doc.chunkIndex ?? null,
    firstSequence: doc.firstSequence ?? null,
    lastSequence: doc.lastSequence ?? null,
    algorithmVersion: ALGORITHM_VERSION,
    computedAt: FieldValue.serverTimestamp(),
  };

  try {
    const decoded = decodeChunk({ ...doc, samples: new Uint8Array(doc.samples ?? []) });
    const metrics = analyzeChunk(decoded, doc.sampleRateHz);
    await metricsRef.set({ ...base, status: "ok", ...metrics });
  } catch (e) {
    if (!(e instanceof ChunkFormatError)) throw e;
    logger.warn("Invalid chunk", { uid, sessionId, chunkId, error: e.message });
    await metricsRef.set({ ...base, status: "invalid", error: e.message });
  }
});
