import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import 'entities/cloud_documents.dart';

/// The backend as seen by the upload engine: anonymous sign-in plus two
/// idempotent document writes.
///
/// Implementations: `FirebaseCloudRemote` (cloud_firestore + firebase_auth),
/// `DisabledCloudRemote` (`ENABLE_FIREBASE=false`), test fakes, and a REST
/// client used by the emulator end-to-end test. All map SDK errors to
/// [CloudFailure] (with `retryable: false` for permission/validation
/// errors) instead of throwing.
abstract interface class CloudRemote {
  /// Signs in anonymously if needed and returns the user id that owns
  /// `users/{uid}/**`.
  Future<Result<String, CloudFailure>> signIn();

  /// Creates or overwrites the session document (allowed by the rules).
  Future<Result<void, CloudFailure>> putSession(
    String uid,
    SessionUpload session,
  );

  /// Writes the chunk document with id [ChunkUpload.docId]. Re-writing an
  /// identical document succeeds (idempotent retry); a different one is
  /// rejected by the append-only rules (permission denied, not retryable).
  Future<Result<void, CloudFailure>> putChunk(String uid, ChunkUpload chunk);
}
