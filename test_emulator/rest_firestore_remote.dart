import 'dart:convert';
import 'dart:io';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/cloud_sync/domain/cloud_remote.dart';
import 'package:ble_prototype/features/cloud_sync/domain/entities/cloud_documents.dart';

/// [CloudRemote] speaking the Firestore and Auth **REST** APIs of the local
/// emulator suite.
///
/// Why not the real `FirebaseCloudRemote`? `flutter test` runs on the host
/// VM without platform plugins, so `cloud_firestore` cannot be used there.
/// This client produces the same documents (same field names and Firestore
/// value types: integer, timestamp, bytes, array) from the same
/// [ChunkUpload] values, so the emulator's rules and the `analyzeChunkOnCreate`
/// trigger see exactly what the app would write. A `PATCH` without an update
/// mask replaces the whole document — the same semantics as `set()`.
class RestFirestoreRemote implements CloudRemote {
  /// [firestoreHost]/[authHost] are `host:port` (the `*_EMULATOR_HOST`
  /// variables set by `firebase emulators:exec`).
  RestFirestoreRemote({
    required this.firestoreHost,
    required this.authHost,
    this.projectId = 'demo-ppg',
  });

  /// Firestore emulator `host:port`.
  final String firestoreHost;

  /// Auth emulator `host:port`.
  final String authHost;

  /// Emulator project id.
  final String projectId;

  final _http = HttpClient();
  String? _idToken;
  String? _uid;

  /// ID token of the signed-in anonymous user.
  String? get idToken => _idToken;

  @override
  Future<Result<String, CloudFailure>> signIn() async {
    if (_uid case final uid?) return Ok(uid);
    final r = await _send(
      'POST',
      Uri.parse(
        'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signUp'
        '?key=demo-api-key',
      ),
      {'returnSecureToken': true},
      auth: false,
    );
    if (r case Err(:final failure)) return Err(failure);
    final body = r.valueOrNull!;
    _idToken = body['idToken'] as String;
    return Ok(_uid = body['localId'] as String);
  }

  @override
  Future<Result<void, CloudFailure>> putSession(String uid, SessionUpload s) =>
      _patch('users/$uid/sessions/${s.sessionId}', {
        'deviceId': _string(s.deviceId),
        'startedAt': _timestamp(s.startedAt),
        'endedAt': s.endedAt == null
            ? {'nullValue': null}
            : _timestamp(s.endedAt!),
        'sampleRateHz': _int(s.sampleRateHz),
      });

  @override
  Future<Result<void, CloudFailure>> putChunk(String uid, ChunkUpload c) =>
      _patch('users/$uid/sessions/${c.sessionId}/chunks/${c.docId}', {
        'sessionId': _string(c.sessionId),
        'chunkIndex': _int(c.chunkIndex),
        'firstSequence': _int(c.firstSequence),
        'lastSequence': _int(c.lastSequence),
        'packetCount': _int(c.packetCount),
        'samplesPerPacket': _int(c.samplesPerPacket),
        'missingSequences': {
          'arrayValue': {
            if (c.missingSequences.isNotEmpty)
              'values': [for (final s in c.missingSequences) _int(s)],
          },
        },
        'startedAt': _timestamp(c.startedAt),
        'sampleRateHz': _int(c.sampleRateHz),
        'deviceId': _string(c.deviceId),
        'encoding': _string(c.encoding),
        'samples': {'bytesValue': base64Encode(c.samples)},
      });

  /// Reads a document as signed-in user; `null` when it does not exist.
  Future<Map<String, dynamic>?> getDocument(String path) async {
    final r = await _send('GET', _docUri(path), null);
    return switch (r) {
      Ok(:final value) => value,
      Err(:final failure) when failure.message.startsWith('404') => null,
      Err(:final failure) => throw StateError(failure.message),
    };
  }

  /// Closes the HTTP client.
  void close() => _http.close(force: true);

  Future<Result<void, CloudFailure>> _patch(
    String path,
    Map<String, Object?> fields,
  ) async => switch (await _send('PATCH', _docUri(path), {'fields': fields})) {
    Ok() => const Ok(null),
    Err(:final failure) => Err(failure),
  };

  Uri _docUri(String path) => Uri.parse(
    'http://$firestoreHost/v1/projects/$projectId/databases/(default)/'
    'documents/$path',
  );

  Future<Result<Map<String, dynamic>, CloudFailure>> _send(
    String method,
    Uri uri,
    Object? body, {
    bool auth = true,
  }) async {
    try {
      final req = await _http.openUrl(method, uri);
      req.headers.contentType = ContentType.json;
      if (auth && _idToken != null) {
        req.headers.set('Authorization', 'Bearer $_idToken');
      }
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Ok(jsonDecode(text) as Map<String, dynamic>);
      }
      return Err(
        CloudFailure(
          '${res.statusCode} $text',
          // 403 = PERMISSION_DENIED (rules), 400 = invalid request.
          retryable: res.statusCode != 403 && res.statusCode != 400,
        ),
      );
    } on IOException catch (e) {
      return Err(CloudFailure(e.toString()));
    }
  }

  static Map<String, Object?> _string(String v) => {'stringValue': v};

  static Map<String, Object?> _int(int v) => {'integerValue': '$v'};

  static Map<String, Object?> _timestamp(DateTime v) => {
    'timestampValue': v.toUtc().toIso8601String(),
  };
}
