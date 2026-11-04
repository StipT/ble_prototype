/** Deterministic PRNG (mulberry32) so signal tests are reproducible. */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function gaussian(random: () => number): number {
  const u1 = 1 - random();
  const u2 = random();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

const BASELINE = 8_000_000;
const AMPLITUDE = 40_000;

/**
 * Port of the app's `PpgSignalGenerator` (lib/features/device_connection/data/fake):
 * sum-of-sines pulse, respiration drift and modulation, Gaussian noise.
 */
export function fakeDeviceSignal(opts: {
  seconds: number;
  heartRateBpm?: number;
  sampleRateHz?: number;
  respirationRateBpm?: number;
  noiseLevel?: number;
  seed?: number;
}): number[] {
  const fs = opts.sampleRateHz ?? 50;
  const hr = opts.heartRateBpm ?? 72;
  const rr = opts.respirationRateBpm ?? 15;
  const noise = opts.noiseLevel ?? 0.03;
  const random = seededRandom(opts.seed ?? 1);
  const dt = 1 / fs;
  let cardiac = 0;
  let resp = 0;
  const out: number[] = [];
  for (let i = 0; i < Math.round(opts.seconds * fs); i++) {
    cardiac = (cardiac + 2 * Math.PI * (hr / 60) * dt) % (2 * Math.PI);
    resp = (resp + 2 * Math.PI * (rr / 60) * dt) % (2 * Math.PI);
    const pulse = Math.sin(cardiac) + 0.45 * Math.sin(2 * cardiac + 0.8) + 0.2 * Math.sin(3 * cardiac + 1.6);
    const value =
      BASELINE + AMPLITUDE * (pulse * (1 + 0.1 * Math.sin(resp)) + 0.6 * Math.sin(resp) + noise * gaussian(random));
    out.push(Math.min(0xffffff, Math.max(0, Math.round(value))));
  }
  return out;
}

/**
 * Signal with a pulse (systolic Gaussian + smaller dicrotic wave) at each
 * given beat time, so the true inter-beat intervals are known exactly.
 */
export function beatSignal(opts: {
  ibisMs: number[];
  sampleRateHz?: number;
  noiseLevel?: number;
  seed?: number;
}): number[] {
  const fs = opts.sampleRateHz ?? 50;
  const random = seededRandom(opts.seed ?? 2);
  const beats: number[] = [];
  let t = 0.5;
  beats.push(t);
  for (const ibi of opts.ibisMs) {
    t += ibi / 1000;
    beats.push(t);
  }
  const total = Math.round((t + 0.5) * fs);
  const out: number[] = [];
  for (let i = 0; i < total; i++) {
    const time = i / fs;
    let pulse = 0;
    for (const b of beats) {
      pulse += Math.exp(-(((time - b) / 0.06) ** 2)) + 0.3 * Math.exp(-(((time - b - 0.25) / 0.08) ** 2));
    }
    const value = BASELINE + AMPLITUDE * (pulse + (opts.noiseLevel ?? 0.01) * gaussian(random));
    out.push(Math.min(0xffffff, Math.max(0, Math.round(value))));
  }
  return out;
}
