import 'dart:async';

import 'package:nfc_manager/ndef_record.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/pairing_tag.dart';
import '../../domain/nfc_reader.dart';
import '../ndef_pairing_codec.dart';

/// Simulated NFC reader for simulators/emulators (which have no NFC
/// hardware) and tests. Selected by `USE_FAKE_NFC=true` (the default).
///
/// [readPairingTag] behaves like a user who holds the phone to the sensor
/// after [tapDelay]: it "reads" [nextMessage] — by default the NDEF message
/// a real tag for [deviceId] would carry — and decodes it with the same
/// [NdefPairingCodec] as the real reader, so the parsing path is exercised
/// even without hardware.
///
/// Knobs (all mutable at runtime, e.g. from tests or a debug panel):
/// [status] to simulate NFC switched off / unsupported, [nextMessage] to
/// "tap" a malformed or foreign tag.
class FakeNfcReader implements NfcReader {
  /// Creates the fake.
  ///
  /// [deviceId] / [deviceName] describe the simulated sensor's tag (DI
  /// passes the `FakePpgDevice` ID so the tap connects to the simulator).
  /// [tapDelay] is how long the simulated user takes to tap. [status] is
  /// what [checkAvailability] reports. [codec] decodes the message.
  FakeNfcReader({
    required String deviceId,
    String? deviceName,
    this.tapDelay = const Duration(milliseconds: 1500),
    this.status = NfcStatus.available,
    NdefPairingCodec codec = const NdefPairingCodec(),
  }) : _codec = codec,
       nextMessage = codec.encode(
         PairingTag(deviceId: deviceId, deviceName: deviceName),
       );

  final NdefPairingCodec _codec;

  /// Time between starting a read and the simulated tap.
  Duration tapDelay;

  /// Availability reported to the app.
  NfcStatus status;

  /// NDEF content of the next tapped tag; `null` simulates a tag that is
  /// not NDEF formatted (e.g. a transit card).
  NdefMessage? nextMessage;

  /// How many reads were started (for assertions).
  int readCount = 0;

  Completer<Result<PairingTag, Failure>>? _pending;
  Timer? _timer;

  /// Whether a read is waiting for the simulated tap.
  bool get isReading => _pending != null;

  @override
  Future<NfcStatus> checkAvailability() async => status;

  @override
  Future<Result<PairingTag, Failure>> readPairingTag() {
    if (_pending != null) {
      return Future.value(
        const Err(NfcUnavailable('An NFC read is already in progress')),
      );
    }
    if (status != NfcStatus.available) {
      return Future.value(
        Err(
          NfcUnavailable(
            status == NfcStatus.disabled
                ? 'NFC is turned off in system settings'
                : 'This device cannot read NFC tags',
          ),
        ),
      );
    }
    readCount++;
    final completer = _pending = Completer();
    _timer = Timer(tapDelay, () => _finish(_codec.decode(nextMessage)));
    return completer.future;
  }

  /// Completes a pending read immediately with the [nextMessage] tag
  /// instead of waiting for [tapDelay].
  void tapNow() {
    if (_pending != null) _finish(_codec.decode(nextMessage));
  }

  @override
  Future<void> cancel() async => _finish(const Err(NfcReadCancelled()));

  void _finish(Result<PairingTag, Failure> result) {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  /// Cancels the pending timer (call from DI dispose / test teardown).
  void dispose() => _finish(const Err(NfcReadCancelled()));
}
