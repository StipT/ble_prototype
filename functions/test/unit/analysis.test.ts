import { describe, expect, it } from "vitest";

import { analyzeChunk, detectPeaks, movingAverage } from "../../src/analysis";
import { DecodedChunk } from "../../src/chunk";
import { beatSignal, fakeDeviceSignal, seededRandom } from "../synth";

function whole(samples: number[]): DecodedChunk {
  return { samples, segments: [{ offset: 0, length: samples.length }], expectedSampleCount: samples.length };
}

describe("analyzeChunk heart rate", () => {
  it.each([50, 72, 110, 150])("recovers %i bpm from the fake-device signal", (bpm) => {
    const m = analyzeChunk(whole(fakeDeviceSignal({ seconds: 10, heartRateBpm: bpm })), 50);
    expect(m.avgHeartRateBpm).not.toBeNull();
    expect(Math.abs(m.avgHeartRateBpm! - bpm)).toBeLessThan(2);
    expect(m.beatCount).toBeGreaterThanOrEqual(Math.floor((bpm / 60) * 10) - 1);
  });

  it("returns null metrics when there are too few beats", () => {
    const m = analyzeChunk(whole(fakeDeviceSignal({ seconds: 1 })), 50);
    expect(m.avgHeartRateBpm).toBeNull();
    expect(m.hrvRmssdMs).toBeNull();
    expect(m.signalQuality.score).toBe(0);
  });
});

describe("analyzeChunk HRV", () => {
  it("is near zero for a perfectly regular rhythm", () => {
    const m = analyzeChunk(whole(beatSignal({ ibisMs: Array(12).fill(800) })), 50);
    expect(m.avgHeartRateBpm).toBeCloseTo(75, 0);
    expect(m.hrvRmssdMs!).toBeLessThan(5);
    expect(m.hrvSdnnMs!).toBeLessThan(5);
  });

  it("measures RMSSD and SDNN of alternating intervals", () => {
    // 760/860 ms alternating: successive differences are all ±100 ms → RMSSD 100, SDNN 50.
    const ibis = Array.from({ length: 12 }, (_, i) => (i % 2 === 0 ? 760 : 860));
    const m = analyzeChunk(whole(beatSignal({ ibisMs: ibis })), 50);
    expect(m.validIbiCount).toBe(12);
    expect(m.avgHeartRateBpm!).toBeCloseTo(60_000 / 810, 0);
    expect(Math.abs(m.hrvRmssdMs! - 100)).toBeLessThan(8);
    expect(Math.abs(m.hrvSdnnMs! - 50)).toBeLessThan(5);
  });

  it("rejects an ectopic-like outlier interval", () => {
    const ibis = [800, 800, 800, 800, 400, 1200, 800, 800, 800, 800];
    const m = analyzeChunk(whole(beatSignal({ ibisMs: ibis })), 50);
    expect(m.validIbiCount).toBe(8);
    expect(m.avgHeartRateBpm!).toBeCloseTo(75, 0);
    expect(m.signalQuality.ibiAcceptance).toBeCloseTo(0.8, 2);
  });

  it("never measures an interval across a packet gap", () => {
    const samples = beatSignal({ ibisMs: Array(12).fill(800) });
    // Drop 0.5 s in the middle: concatenating would create a short fake interval.
    const cut = 250;
    const kept = [...samples.slice(0, cut), ...samples.slice(cut + 25)];
    const decoded: DecodedChunk = {
      samples: kept,
      segments: [
        { offset: 0, length: cut },
        { offset: cut, length: kept.length - cut },
      ],
      expectedSampleCount: samples.length,
    };
    const m = analyzeChunk(decoded, 50);
    expect(m.validIbiCount).toBe(m.beatCount - 2);
    expect(m.signalQuality.ibiAcceptance).toBe(1);
    expect(m.hrvRmssdMs!).toBeLessThan(5);
  });
});

describe("analyzeChunk signal quality", () => {
  it("rates the clean fake-device signal as good", () => {
    const q = analyzeChunk(whole(fakeDeviceSignal({ seconds: 10 })), 50).signalQuality;
    expect(q.label).toBe("good");
    expect(q.score).toBeGreaterThan(0.9);
    expect(q.snrDb).toBeGreaterThan(15);
    expect(q.coverage).toBe(1);
    expect(q.clippedFraction).toBe(0);
  });

  it("rates a very noisy signal as poor", () => {
    const q = analyzeChunk(whole(fakeDeviceSignal({ seconds: 10, noiseLevel: 1.5 })), 50).signalQuality;
    expect(q.label).toBe("poor");
    expect(q.score).toBeLessThan(0.4);
  });

  it("rates pure noise as poor", () => {
    const random = seededRandom(7);
    const noise = Array.from({ length: 500 }, () => Math.round(8_000_000 + 40_000 * (random() - 0.5)));
    expect(analyzeChunk(whole(noise), 50).signalQuality.label).toBe("poor");
  });

  it("scores a flat line as zero", () => {
    const m = analyzeChunk(whole(Array(500).fill(8_000_000)), 50);
    expect(m.beatCount).toBe(0);
    expect(m.signalQuality.score).toBe(0);
  });

  it("penalises missing packets via coverage", () => {
    const samples = fakeDeviceSignal({ seconds: 10 });
    const decoded: DecodedChunk = {
      samples: samples.slice(0, 250),
      segments: [{ offset: 0, length: 250 }],
      expectedSampleCount: 500,
    };
    const q = analyzeChunk(decoded, 50).signalQuality;
    expect(q.coverage).toBe(0.5);
    expect(q.label).toBe("fair");
  });

  it("penalises clipping at the ADC rails", () => {
    const samples = fakeDeviceSignal({ seconds: 10 }).map((s, i) => (i % 2 === 0 ? 0xffffff : s));
    expect(analyzeChunk(whole(samples), 50).signalQuality.clippedFraction).toBe(0.5);
  });
});

describe("helpers", () => {
  it("movingAverage shrinks the window at the edges", () => {
    expect(movingAverage([1, 2, 3, 4, 5], 3)).toEqual([1.5, 2, 3, 4, 4.5]);
  });

  it("detectPeaks refines peak position with parabolic interpolation", () => {
    const y = Array.from({ length: 21 }, (_, i) => Math.max(0, 1 - ((i - 10.3) / 5) ** 2));
    const [peak] = detectPeaks(y, 5);
    expect(peak).toBeCloseTo(10.3, 5);
  });
});
