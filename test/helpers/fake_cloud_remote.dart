import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/cloud_sync/domain/cloud_remote.dart';
import 'package:ble_prototype/features/cloud_sync/domain/entities/cloud_documents.dart';

/// In-memory [CloudRemote] that mimics the append-only rules and can be
/// scripted to fail.
class FakeCloudRemote implements CloudRemote {
  /// Uid returned by [signIn].
  String uid = 'test-uid';

  /// Failure returned by [signIn] while set.
  CloudFailure? signInFailure;

  /// Failure returned by [putSession] while set.
  CloudFailure? sessionFailure;

  /// Failures returned by the next [putChunk] calls, consumed in order.
  final List<CloudFailure> chunkFailures = [];

  /// Failure returned by every [putChunk] while set.
  CloudFailure? alwaysFailChunks;

  /// Stored session docs by `uid/sessionId`.
  final Map<String, SessionUpload> sessions = {};

  /// Stored chunk docs by `uid/docId`.
  final Map<String, ChunkUpload> chunks = {};

  /// Every call in order, e.g. `signIn`, `session:<id>`, `chunk:<docId>`.
  final List<String> calls = [];

  @override
  Future<Result<String, CloudFailure>> signIn() async {
    calls.add('signIn');
    if (signInFailure case final f?) return Err(f);
    return Ok(uid);
  }

  @override
  Future<Result<void, CloudFailure>> putSession(
    String uid,
    SessionUpload session,
  ) async {
    calls.add('session:${session.sessionId}');
    if (sessionFailure case final f?) return Err(f);
    sessions['$uid/${session.sessionId}'] = session;
    return const Ok(null);
  }

  @override
  Future<Result<void, CloudFailure>> putChunk(
    String uid,
    ChunkUpload chunk,
  ) async {
    calls.add('chunk:${chunk.docId}');
    if (alwaysFailChunks case final f?) return Err(f);
    if (chunkFailures.isNotEmpty) return Err(chunkFailures.removeAt(0));
    final key = '$uid/${chunk.docId}';
    final existing = chunks[key];
    // Append-only rules: only an identical re-write is allowed.
    if (existing != null && existing != chunk) {
      return const Err(
        CloudFailure('permission-denied: chunk changed', retryable: false),
      );
    }
    chunks[key] = chunk;
    return const Ok(null);
  }
}
