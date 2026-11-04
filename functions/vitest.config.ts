import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    // Emulator suites share one Firestore emulator; run files sequentially.
    fileParallelism: false,
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
