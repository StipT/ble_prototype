import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/cloud_remote.dart';
import '../domain/entities/cloud_documents.dart';

/// [CloudRemote] used when Firebase is off (`ENABLE_FIREBASE=false`, or
/// initialization failed): every call fails before any chunk is touched,
/// so local data simply stays `pending`.
class DisabledCloudRemote implements CloudRemote {
  /// [reason] is shown in the sync panel.
  const DisabledCloudRemote([
    this.reason = 'Cloud sync disabled (ENABLE_FIREBASE=false)',
  ]);

  /// Why cloud sync is unavailable.
  final String reason;

  @override
  Future<Result<String, CloudFailure>> signIn() async =>
      Err(CloudFailure(reason, retryable: false));

  @override
  Future<Result<void, CloudFailure>> putSession(
    String uid,
    SessionUpload session,
  ) async => Err(CloudFailure(reason, retryable: false));

  @override
  Future<Result<void, CloudFailure>> putChunk(
    String uid,
    ChunkUpload chunk,
  ) async => Err(CloudFailure(reason, retryable: false));
}
