# Backend: Firestore + Cloud Functions (emulator-first)

Files: `../firebase.json`, `../.firebaserc` (demo project `demo-ppg`, so the emulators need no real
project or login), `../firestore.rules`, `../firestore.indexes.json`, and this `functions/` package
(TypeScript, Node 20 runtime, firebase-functions v2 API).

Emulator ports: Auth 9099, Firestore 8080, Functions 5001, Emulator UI 4000.

## Requirements

- Node 20+ (the deployed runtime is Node 20; locally any newer Node works — the emulator warns
  `requested "node" version "20" doesn't match` and uses the host Node).
- firebase-tools 15+, which needs **Java 21+** for the Firestore emulator. On macOS:
  `brew install openjdk@21` (keg-only) and prefix commands with
  `PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH`.

## Commands (run in `functions/`)

```sh
npm install
npm test                    # pure unit tests (chunk decoding + HR/HRV/quality analysis), no emulator
npm run test:emulators      # build, start auth+firestore+functions emulators, run rules + trigger tests
npm run test:all            # typecheck + both of the above
npm run serve               # build and start all emulators (UI at http://127.0.0.1:4000)
npm run test:flutter-e2e    # build, start emulators, run the Flutter client E2E (`flutter test test_emulator`)
```

## Flutter client (issue 06)

- Run the app against the emulators: `npm run serve` here, then
  `flutter run --dart-define=USE_EMULATOR=true` (optionally `--dart-define=EMULATOR_HOST=<ip>`,
  default `localhost`). On the Android emulator FlutterFire maps `localhost` to `10.0.2.2`
  automatically; for a physical device use your machine's LAN IP and start the emulators bound to
  `0.0.0.0` (`host` in `firebase.json`). Android may also need a cleartext network-security config for
  that host. `--dart-define=ENABLE_FIREBASE=false` runs fully offline (uploads are disabled).
- `lib/firebase_options.dart` is a **stub** for project `demo-ppg` (only valid against emulators). For a
  real project run `flutterfire configure`, enable **Anonymous** sign-in, and
  `firebase deploy --only firestore:rules,functions`.
- Flutter tests never touch Firebase plugins: `CloudRemote` is faked in `test/`. The E2E in
  `../test_emulator/` drives the real `DriftCloudSyncRepository` + `ChunkEncoder` through a REST
  `CloudRemote` (`rest_firestore_remote.dart`) against the emulators, so it checks that the docs pass
  `firestore.rules` and that `analyzeChunkOnCreate` writes metrics. `test_emulator/` is outside `test/`,
  so plain `flutter test` skips it.

## Data model

All data lives under `users/{uid}` where `uid` is the Firebase Auth (anonymous) user id. Only that
user can read anything under `users/{uid}/**`; writes are whitelisted per collection below.

### `users/{uid}/sessions/{sessionId}` — client-writable (create/update, no delete)

| field          | type                 | notes                                  |
|----------------|----------------------|----------------------------------------|
| `deviceId`     | string (1..128)      | required                               |
| `startedAt`    | timestamp            | required                               |
| `sampleRateHz` | int (1..1000)        | required                               |
| `endedAt`      | timestamp \| null    | optional, set when the session ends    |
| `updatedAt`    | timestamp            | optional                               |

No other fields are allowed.

### `users/{uid}/sessions/{sessionId}/chunks/{sessionId}_{chunkIndex}` — append-only

One local Drift chunk (≤ 100 packets × 5 samples = 10 s at 50 Hz). The document id **must** be
`${sessionId}_${chunkIndex}`. Exactly these fields, all required:

| field              | type      | rule / meaning                                                         |
|--------------------|-----------|------------------------------------------------------------------------|
| `sessionId`        | string    | must equal the path `sessionId`                                        |
| `chunkIndex`       | int ≥ 0   | `sequence ~/ 100`                                                       |
| `firstSequence`    | int       | lowest stored sequence, `≥ chunkIndex*100`                              |
| `lastSequence`     | int       | highest stored sequence, `< (chunkIndex+1)*100`, `≥ firstSequence`      |
| `packetCount`      | int       | `1 ≤ packetCount ≤ lastSequence-firstSequence+1`                        |
| `samplesPerPacket` | int 1..64 | 5 for the current codec                                                 |
| `missingSequences` | int[]     | sequences in `(firstSequence, lastSequence)` not stored, ascending; size must be `span - packetCount` (usually `[]`) |
| `startedAt`        | timestamp | timestamp of the earliest packet                                        |
| `sampleRateHz`     | int       | from the session                                                        |
| `deviceId`         | string    | from the session                                                        |
| `encoding`         | string    | must be `"gzip-u24le"`                                                  |
| `samples`          | Bytes     | `gzip(SamplePacking.pack(allSamples))`, ≤ 512 KiB                       |

`samples` = all samples of the stored packets concatenated in ascending sequence order, packed as
unsigned 24-bit little-endian (`lib/core/database/sample_packing.dart`), then gzip-compressed (Dart:
`GZipCodec().encode`). The function checks that the unpacked length is `packetCount * samplesPerPacket`.

Append-only: create is validated as above; an update is allowed **only** if the new document is
identical to the stored one (an idempotent upload retry with `set()`, since client SDKs have no
`create()`); any change or delete is denied. Do not put server timestamps in chunk docs — they would
make retries non-identical.

### `users/{uid}/sessions/{sessionId}/metrics/{chunkId}` — written only by the function

`analyzeChunkOnCreate` (Firestore `onDocumentCreated` trigger on the chunk path) writes:

| field                                     | type             | notes                                          |
|-------------------------------------------|------------------|------------------------------------------------|
| `status`                                  | `"ok"`/`"invalid"` | `invalid` when the payload does not decode    |
| `error`                                   | string           | only when `invalid`                            |
| `sessionId`, `chunkId`, `chunkIndex`, `firstSequence`, `lastSequence` | | copied from the chunk         |
| `avgHeartRateBpm`                         | number \| null   | null with < 3 accepted beats intervals         |
| `hrvRmssdMs`, `hrvSdnnMs`                 | number \| null   | HRV (RMSSD of successive IBIs, SDNN)           |
| `beatCount`, `validIbiCount`              | int              |                                                |
| `signalQuality`                           | map              | `score` 0..1, `label` good/fair/poor, `snrDb`, `coverage`, `ibiAcceptance`, `clippedFraction` |
| `algorithmVersion`                        | int              | currently 1                                    |
| `computedAt`                              | timestamp        | server time                                    |

Results go to a separate doc because the chunk is append-only; the write is a deterministic `set`, so
event redelivery is harmless.

### Algorithm (`src/analysis.ts`)

Per gap-free run of packets (split at `missingSequences`, runs < 2 s skipped): baseline removal with a
1.5 s centred moving average, 0.1 s moving-average low-pass, peak detection (> 40 % of the 95th
percentile, 0.3 s refractory) with parabolic sub-sample refinement, inter-beat intervals only within a
run. IBIs outside 40–180 bpm or > 30 % from the median are rejected. Quality score =
`coverage × ibiAcceptance × snrScore × (1 − clippedFraction)`, `snrScore` maps 3..15 dB to 0..1;
`good` ≥ 0.7, `fair` ≥ 0.4.

Production note: Cloud Storage would be the better home for large sample blobs; Firestore Bytes keep this
prototype to one SDK.
