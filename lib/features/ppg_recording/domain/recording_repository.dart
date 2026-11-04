import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../../device_connection/domain/entities/ppg_packet.dart';
import 'entities/sequence_range.dart';
import 'entities/session.dart';

/// Local persistence of recording sessions. The database is the source of
/// truth; the UI observes it through [watchSessions].
abstract interface class RecordingRepository {
  /// Creates a new open session for [deviceId] starting at [startedAt].
  Future<Result<Session, Failure>> startSession({
    required String deviceId,
    required DateTime startedAt,
  });

  /// Closes session [sessionId] at [endedAt].
  Future<Result<void, Failure>> endSession(String sessionId, DateTime endedAt);

  /// Persists [packets] for [sessionId] in **one transaction** and updates the
  /// affected chunk aggregates. Packets already stored (same sequence) are
  /// ignored, so live and history copies never duplicate. Returns the number
  /// of newly inserted packets.
  Future<Result<int, Failure>> savePackets(
    String sessionId,
    List<PpgPacket> packets,
  );

  /// Sequence ranges of session [sessionId] that are **not** stored yet and
  /// that the device can still replay, oldest first.
  ///
  /// Two kinds of holes are reported:
  /// * **gaps** between stored packets (live notifications lost in the air,
  ///   or the link was down for a while and live streaming resumed later);
  /// * the **tail** after the newest stored packet, up to [upTo] (the
  ///   device's `latestSequence`): what the device recorded while the app
  ///   was not listening and that no live packet has covered yet.
  ///
  /// Every range is clipped to [notBefore]..[upTo] — the device backlog
  /// (`oldestSequence..latestSequence`); older data was overwritten in the
  /// device's ring buffer and can never be fetched. A session with no
  /// stored packet has no known starting point and yields an empty list.
  Future<Result<List<SequenceRange>, Failure>> missingRanges(
    String sessionId, {
    required int notBefore,
    required int upTo,
  });

  /// The currently open session, if any (e.g. after an app restart).
  Future<Result<Session?, Failure>> activeSession();

  /// All sessions, newest first, with aggregates; re-emits on every change.
  Stream<List<SessionSummary>> watchSessions();
}
