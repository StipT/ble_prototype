import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Upload lifecycle of a chunk: `pending -> uploading -> synced | failed`.
///
/// `failed` is terminal only after the per-chunk retry cap; a manual
/// "Sync now" moves failed chunks back to `pending`.
enum ChunkSyncState {
  /// Waiting to be uploaded.
  pending,

  /// Upload in flight (reset to `pending` on app start if the app died
  /// mid-upload).
  uploading,

  /// Stored in Firestore.
  synced,

  /// Retry cap reached.
  failed,
}

/// One recording session.
@DataClassName('SessionRow')
class Sessions extends Table {
  /// Random 128-bit hex ID, also used in the Firestore path.
  TextColumn get id => text()();

  /// OS identifier of the wearable that produced the data.
  TextColumn get deviceId => text()();

  /// When the user pressed "Record".
  DateTimeColumn get startedAt => dateTime()();

  /// When the user pressed "Stop"; `null` while recording.
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Samples per second of the stored signal.
  IntColumn get sampleRateHz => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Raw packets. The composite primary key makes inserts idempotent: a
/// packet received live and again from history is stored once.
@DataClassName('PacketRow')
class Packets extends Table {
  /// Owning session.
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// Device sequence number.
  IntColumn get sequence => integer()();

  /// Time of the first sample.
  DateTimeColumn get timestamp => dateTime()();

  /// Samples packed as unsigned 24-bit little-endian (3 bytes each).
  BlobColumn get samples => blob()();

  /// Whether the packet arrived through history sync.
  BoolColumn get fromHistory => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {sessionId, sequence};
}

/// ~10 s groups of packets; the unit of cloud upload.
@DataClassName('ChunkRow')
class Chunks extends Table {
  /// Owning session.
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// `sequence ~/ packetsPerChunk`; with [sessionId] forms the Firestore
  /// document ID `sessionId_chunkIndex`.
  IntColumn get chunkIndex => integer()();

  /// Packets currently stored for this chunk.
  IntColumn get packetCount => integer()();

  /// Lowest stored sequence.
  IntColumn get firstSequence => integer()();

  /// Highest stored sequence.
  IntColumn get lastSequence => integer()();

  /// Timestamp of the earliest packet (used for pruning age).
  DateTimeColumn get startedAt => dateTime()();

  /// Upload state.
  TextColumn get syncState => textEnum<ChunkSyncState>()();

  /// Failed upload attempts so far.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Earliest time of the next retry (exponential backoff).
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Message of the last upload failure.
  TextColumn get lastError => text().nullable()();

  /// When the upload succeeded.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  /// When the local packets were pruned (row kept as a tombstone so the
  /// chunk is never uploaded twice).
  DateTimeColumn get prunedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId, chunkIndex};
}

/// The local SQLite database — the app's source of truth.
@DriftDatabase(tables: [Sessions, Packets, Chunks])
class AppDatabase extends _$AppDatabase {
  /// Opens [executor]; use [AppDatabase.open] in the app and
  /// `NativeDatabase.memory()` in tests.
  AppDatabase(super.executor);

  /// Opens the on-device database file `ppg.sqlite`.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'ppg'));

  /// Packets per chunk: 100 packets × 5 samples / 50 Hz = 10 s.
  static const packetsPerChunk = 100;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
