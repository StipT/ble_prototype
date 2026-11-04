import type { DecodedChunk } from "./chunk";

/** Bumped whenever the algorithm changes so stored metrics can be recomputed selectively. */
export const ALGORITHM_VERSION = 1;

/** Physiologically plausible inter-beat intervals: 40–180 bpm. */
const MIN_IBI_MS = 60_000 / 180;
const MAX_IBI_MS = 60_000 / 40;
/** IBIs further than this from the chunk median are treated as artefacts. */
const MAX_IBI_DEVIATION = 0.3;
/** Segments shorter than this hold too few beats to analyse. */
const MIN_SEGMENT_SECONDS = 2;
const MAX_SAMPLE = 0xffffff;

export type QualityLabel = "good" | "fair" | "poor";

export interface SignalQuality {
  /** 0..1, product of the factors below (with SNR mapped to 0..1). */
  score: number;
  label: QualityLabel;
  /** Pulse-band power vs. high-frequency residual, in dB. */
  snrDb: number;
  /** Share of the chunk's time span that was analysable (received, in long-enough runs). */
  coverage: number;
  /** Share of detected inter-beat intervals that passed the plausibility checks. */
  ibiAcceptance: number;
  /** Share of samples stuck at the ADC rails (0 or 0xFFFFFF). */
  clippedFraction: number;
}

export interface ChunkMetrics {
  /** Mean heart rate from accepted inter-beat intervals; null if fewer than 3. */
  avgHeartRateBpm: number | null;
  /** HRV: root mean square of successive IBI differences; null if fewer than 2 pairs. */
  hrvRmssdMs: number | null;
  /** HRV: standard deviation of accepted IBIs; null if fewer than 3. */
  hrvSdnnMs: number | null;
  beatCount: number;
  validIbiCount: number;
  signalQuality: SignalQuality;
}

/**
 * Computes heart rate, HRV and a signal-quality score from one chunk.
 *
 * Pipeline per gap-free segment: remove baseline wander (1.5 s centred moving
 * average, which also removes respiration drift), low-pass with a 0.1 s
 * moving average, detect systolic peaks (local maxima above 40 % of the 95th
 * percentile, 0.3 s refractory period), refine peak times with parabolic
 * interpolation, and take inter-beat intervals (IBIs) only within a segment
 * so packet gaps never produce fake long beats.
 */
export function analyzeChunk(chunk: DecodedChunk, sampleRateHz: number): ChunkMetrics {
  const fs = sampleRateHz;
  const baselineWindow = oddWindow(1.5 * fs);
  const lowPassWindow = Math.max(3, oddWindow(0.1 * fs));
  const refractory = Math.max(1, Math.round(0.3 * fs));

  let signalPower = 0;
  let noisePower = 0;
  let analysedSamples = 0;
  let beatCount = 0;
  const ibiRuns: number[][] = [];

  for (const segment of chunk.segments) {
    if (segment.length < MIN_SEGMENT_SECONDS * fs) continue;
    const x = chunk.samples.slice(segment.offset, segment.offset + segment.length);
    const baseline = movingAverage(x, baselineWindow);
    const highPassed = x.map((v, i) => v - baseline[i]);
    const y = movingAverage(highPassed, lowPassWindow);
    for (let i = 0; i < y.length; i++) {
      signalPower += y[i] * y[i];
      const r = highPassed[i] - y[i];
      noisePower += r * r;
    }
    analysedSamples += x.length;

    const peaks = detectPeaks(y, refractory);
    beatCount += peaks.length;
    const ibis: number[] = [];
    for (let i = 1; i < peaks.length; i++) {
      ibis.push(((peaks[i] - peaks[i - 1]) * 1000) / fs);
    }
    if (ibis.length > 0) ibiRuns.push(ibis);
  }

  const allIbis = ibiRuns.flat();
  const inRange = allIbis.filter((ibi) => ibi >= MIN_IBI_MS && ibi <= MAX_IBI_MS);
  const med = inRange.length > 0 ? median(inRange) : 0;
  const accepted = (ibi: number) =>
    ibi >= MIN_IBI_MS && ibi <= MAX_IBI_MS && Math.abs(ibi - med) <= MAX_IBI_DEVIATION * med;

  const valid = allIbis.filter(accepted);
  const successiveDiffs: number[] = [];
  for (const run of ibiRuns) {
    for (let i = 1; i < run.length; i++) {
      if (accepted(run[i - 1]) && accepted(run[i])) successiveDiffs.push(run[i] - run[i - 1]);
    }
  }

  const meanIbi = valid.length > 0 ? mean(valid) : 0;
  const avgHeartRateBpm = valid.length >= 3 ? round(60_000 / meanIbi, 1) : null;
  const hrvRmssdMs =
    successiveDiffs.length >= 2 ? round(Math.sqrt(mean(successiveDiffs.map((d) => d * d))), 1) : null;
  const hrvSdnnMs =
    valid.length >= 3 ? round(Math.sqrt(mean(valid.map((v) => (v - meanIbi) ** 2))), 1) : null;

  const clipped = chunk.samples.filter((s) => s <= 0 || s >= MAX_SAMPLE).length;
  const clippedFraction = chunk.samples.length > 0 ? clipped / chunk.samples.length : 0;
  const coverage = chunk.expectedSampleCount > 0 ? analysedSamples / chunk.expectedSampleCount : 0;
  const ibiAcceptance = allIbis.length > 0 ? valid.length / allIbis.length : 0;
  const snrDb =
    signalPower === 0 ? -60 : noisePower === 0 ? 60 : clamp(10 * Math.log10(signalPower / noisePower), -60, 60);
  const snrScore = clamp((snrDb - 3) / 12, 0, 1);
  const score = round(coverage * ibiAcceptance * snrScore * (1 - clippedFraction), 3);

  return {
    avgHeartRateBpm,
    hrvRmssdMs,
    hrvSdnnMs,
    beatCount,
    validIbiCount: valid.length,
    signalQuality: {
      score,
      label: score >= 0.7 ? "good" : score >= 0.4 ? "fair" : "poor",
      snrDb: round(snrDb, 1),
      coverage: round(coverage, 3),
      ibiAcceptance: round(ibiAcceptance, 3),
      clippedFraction: round(clippedFraction, 4),
    },
  };
}

/**
 * Returns fractional sample positions of systolic peaks in [y]. Peaks closer
 * than [refractory] samples compete; the higher one wins.
 */
export function detectPeaks(y: readonly number[], refractory: number): number[] {
  if (y.length < 3) return [];
  const threshold = 0.4 * percentile(y, 0.95);
  if (!(threshold > 0)) return [];

  const peaks: number[] = [];
  for (let i = 1; i < y.length - 1; i++) {
    if (y[i] < threshold || y[i] <= y[i - 1] || y[i] < y[i + 1]) continue;
    const last = peaks[peaks.length - 1];
    if (last !== undefined && i - last < refractory) {
      if (y[i] > y[last]) peaks[peaks.length - 1] = i;
      continue;
    }
    peaks.push(i);
  }
  return peaks.map((i) => {
    const denom = y[i - 1] - 2 * y[i] + y[i + 1];
    return denom === 0 ? i : i + (0.5 * (y[i - 1] - y[i + 1])) / denom;
  });
}

/** Centred moving average; the window shrinks at the edges. */
export function movingAverage(x: readonly number[], window: number): number[] {
  const half = Math.floor(window / 2);
  const prefix = new Float64Array(x.length + 1);
  for (let i = 0; i < x.length; i++) prefix[i + 1] = prefix[i] + x[i];
  return x.map((_, i) => {
    const lo = Math.max(0, i - half);
    const hi = Math.min(x.length, i + half + 1);
    return (prefix[hi] - prefix[lo]) / (hi - lo);
  });
}

function oddWindow(samples: number): number {
  const n = Math.max(1, Math.round(samples));
  return n % 2 === 0 ? n + 1 : n;
}

function percentile(x: readonly number[], p: number): number {
  const sorted = [...x].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

function median(x: readonly number[]): number {
  const sorted = [...x].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

function mean(x: readonly number[]): number {
  return x.reduce((a, b) => a + b, 0) / x.length;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

function round(v: number, digits: number): number {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
}
