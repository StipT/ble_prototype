# PPG BLE Sync — Vertical Slice Spec

## 1. Goal
Offline-first Flutter app (iOS + Android) that syncs PPG (photoplethysmography) data from a BLE wearable
into a local DB, then uploads it to Firebase. Showcases BLoC state management on a clean architecture.
Bounded vertical slice. Existing project name and bundle IDs are unchanged.

## 2. Non-goals
UI polish, tablet layouts, localization, full-device integration tests, real-device protocol (placeholder only).

## 3. Stack
- Flutter 3.38 / Dart ^3.9; `flutter_bloc`, `bloc_concurrency`, `hydrated_bloc`, `equatable`, `get_it` (hand-written wiring)
- BLE: `flutter_reactive_ble`; NFC: NFC plugin behind an interface; `permission_handler`; `connectivity_plus`
- Local: Drift (SQLite)
- Backend: Firebase Auth (anonymous), Firestore, Cloud Functions (TypeScript, Node 20); emulator-first
- Tests: `bloc_test`, `mocktail`, Drift in-memory, Functions + rules tests on emulator

## 4. Architecture
Feature-first, clean layers per feature (`domain` / `data` / `presentation`):
```
lib/core            errors (sealed Failure), Result<T,Failure>, get_it setup, AppBlocObserver, theme
lib/features/
  device_connection  scan, connect, reconnect, battery/status
  ppg_recording      live stream -> batched Drift writes, waveform
  device_sync        history download, resume by sequence number
  cloud_sync         upload engine, retry/backoff, pruning
  pairing_nfc        tap-to-pair
```
Domain returns `Result<T, Failure>`; failures: `BlePermissionDenied`, `BluetoothOff`, `DeviceNotFound`,
`ConnectionLost`, `ProtocolError`, `NfcUnavailable`.

## 5. Two sync flows
1. **Device sync** (BLE): live PPG + history backlog (device stores samples while disconnected; app requests
   missed ranges by sequence number; resume from last stored sequence).
2. **Cloud sync**: push local DB to Firestore.

## 6. BLE / NFC
- Placeholder GATT protocol isolated in one `PpgPacketCodec`: PPG notify characteristic, control characteristic
  (start/stop/sync/history request), status/battery characteristic.
- Packet: sequence number, timestamp, N x 24-bit samples, little-endian. Malformed packets -> `ProtocolError`.
- Real adapter and `FakePpgDevice` implement the same interface; switch by DI flag.
- `FakePpgDevice`: sum-of-sines pulse + respiration drift + noise, configurable HR; faults: random disconnect,
  dropped packets (sequence gaps), stored backlog. Debug panel triggers faults.
- NFC tap-to-pair: read tag containing device ID -> connect; fake implementation for simulators.
- Reconnect: capped exponential backoff, resume from last stored sequence.

## 7. Documentation requirement (learning-oriented)
- Every BLE/NFC class, method, and parameter has detailed `///` dartdoc with the "why" and gotchas
  (MTU, notify vs indicate, write with/without response, iOS vs Android differences, permissions, etc.).
- `docs/BLE_NFC_PRIMER.md`: concepts + flow diagram linking to code.

## 8. Offline-first data
- Drift is the source of truth; UI reads from DB. Live waveform reads in-memory stream, drawn by `CustomPainter`.
- Packets written in batches (~250 ms or 50 packets) in one transaction. Chunk `syncState`:
  `pending -> uploading -> synced | failed`.
- Cloud upload triggers: connectivity regained, session end, manual "Sync now". Exponential backoff, per-chunk retry cap.
- Idempotent: Firestore doc ID `sessionId_chunkIndex`. Cloud is append-only.
- Prune only `synced` chunks older than 7 days (configurable).

## 9. Backend
- Anonymous Auth; data under `users/{uid}/sessions/{sessionId}` and `.../chunks/{sessionId_chunkIndex}`
  (~10 s of samples as compressed `Bytes` blob). Cloud Storage noted as the production alternative.
- Cloud Function: Firestore trigger on chunk create -> computes avg HR, HRV, signal quality, writes back.
- `firestore.rules`: access only to own `users/{uid}/**`.
- Repo contains `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `functions/`, stub `firebase_options.dart`.
  `--dart-define=USE_EMULATOR=true` -> Auth 9099, Firestore 8080, Functions 5001. Real project: `flutterfire configure`.

## 10. State-management showcase
`Bloc` + `Cubit`; `droppable`/`restartable`/`sequential` transformers; `BlocObserver`; `Equatable` + sealed states;
`emit.forEach`/`emit.onEach`; `BlocSelector`, `BlocListener`, `MultiBlocProvider`, `RepositoryProvider`,
`buildWhen`/`listenWhen`; `HydratedBloc` (last paired device); `PermissionCubit`.

## 11. Permissions
- Android: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`, legacy BLUETOOTH/ADMIN + location (API <=30),
  NFC permission, NFC `uses-feature` required=false.
- iOS: `NSBluetoothAlwaysUsageDescription`, `NFCReaderUsageDescription`, NFC tag entitlement (paid account for devices).

## 12. Tests
Codec unit tests (+ malformed corpus); `bloc_test` for every bloc; Drift in-memory repository tests;
Functions tests on emulator; Firestore rules tests.

## 13. Definition of done
`flutter analyze` clean; all tests pass; `flutter build apk --debug` succeeds; iOS build attempted if Xcode
available; README explains emulators and fake device usage.
