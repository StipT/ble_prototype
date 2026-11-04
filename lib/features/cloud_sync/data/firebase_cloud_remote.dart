import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/cloud_remote.dart';
import '../domain/entities/cloud_documents.dart';

/// [CloudRemote] on the Firebase SDKs (anonymous Auth + Firestore).
///
/// The SDK instances are resolved lazily through the getters, so creating
/// this object never touches Firebase; `Firebase.initializeApp` must have
/// run before the first call.
class FirebaseCloudRemote implements CloudRemote {
  /// [auth]/[firestore] default to the default-app instances. [timeout]
  /// bounds every call: Firestore writes only complete once the server
  /// acknowledges them, which never happens while offline.
  FirebaseCloudRemote({
    FirebaseAuth Function()? auth,
    FirebaseFirestore Function()? firestore,
    this.timeout = const Duration(seconds: 20),
  }) : _auth = auth ?? (() => FirebaseAuth.instance),
       _firestore = firestore ?? (() => FirebaseFirestore.instance);

  final FirebaseAuth Function() _auth;
  final FirebaseFirestore Function() _firestore;

  /// Maximum duration of a single backend call.
  final Duration timeout;

  @override
  Future<Result<String, CloudFailure>> signIn() => _guard(() async {
    final auth = _auth();
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('anonymous sign-in returned no user');
    return user.uid;
  });

  @override
  Future<Result<void, CloudFailure>> putSession(
    String uid,
    SessionUpload session,
  ) => _guard(
    () => _firestore()
        .doc('users/$uid/sessions/${session.sessionId}')
        .set(sessionToFirestore(session)),
  );

  @override
  Future<Result<void, CloudFailure>> putChunk(String uid, ChunkUpload chunk) =>
      _guard(
        () => _firestore()
            .doc('users/$uid/sessions/${chunk.sessionId}/chunks/${chunk.docId}')
            .set(chunkToFirestore(chunk)),
      );

  Future<Result<T, CloudFailure>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body().timeout(timeout));
    } on TimeoutException {
      return const Err(CloudFailure('backend call timed out'));
    } on FirebaseException catch (e) {
      return Err(
        CloudFailure(
          '${e.plugin}/${e.code}: ${e.message}',
          retryable: !_permanentCodes.contains(e.code),
        ),
      );
    } on Object catch (e) {
      // e.g. "[core/no-app]" when Firebase was never initialized.
      return Err(CloudFailure(e.toString()));
    }
  }

  /// Error codes for which retrying the identical request cannot help.
  static const _permanentCodes = {
    'permission-denied',
    'invalid-argument',
    'already-exists',
    'failed-precondition',
    'out-of-range',
    'unimplemented',
    'admin-restricted-operation',
    'operation-not-allowed',
  };
}

/// Session document fields (`firestore.rules` `validSession`).
Map<String, Object?> sessionToFirestore(SessionUpload s) => {
  'deviceId': s.deviceId,
  'startedAt': Timestamp.fromDate(s.startedAt),
  'endedAt': s.endedAt == null ? null : Timestamp.fromDate(s.endedAt!),
  'sampleRateHz': s.sampleRateHz,
};

/// Chunk document fields (`firestore.rules` `validChunk`): ints stay Dart
/// `int` (Firestore integer, the rules check `is int`), [ChunkUpload.samples]
/// becomes a `Blob` (Firestore Bytes), times become `Timestamp`s. No server
/// timestamps: a retry must write an identical document.
Map<String, Object?> chunkToFirestore(ChunkUpload c) => {
  'sessionId': c.sessionId,
  'chunkIndex': c.chunkIndex,
  'firstSequence': c.firstSequence,
  'lastSequence': c.lastSequence,
  'packetCount': c.packetCount,
  'samplesPerPacket': c.samplesPerPacket,
  'missingSequences': List<int>.of(c.missingSequences),
  'startedAt': Timestamp.fromDate(c.startedAt),
  'sampleRateHz': c.sampleRateHz,
  'deviceId': c.deviceId,
  'encoding': c.encoding,
  'samples': Blob(Uint8List.fromList(c.samples)),
};
