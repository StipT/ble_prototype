import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/entities/pairing_tag.dart';
import '../domain/nfc_reader.dart';
import 'ndef_pairing_codec.dart';

/// [NfcReader] backed by the `nfc_manager` 4.x plugin (Android + iOS).
///
/// ## nfc_manager 4.x in short
/// * `NfcManager.instance` is a per-platform singleton; it throws
///   `UnsupportedError` on desktop/web, so it is only touched lazily.
/// * `startSession(pollingOptions:, onDiscovered:)` starts polling; every
///   discovered tag arrives as an opaque `NfcTag`. 4.x removed the old
///   cross-platform `Ndef` class from the core package: you convert the
///   `NfcTag` with a *platform-specific* class — `NdefAndroid.from(tag)` /
///   `NdefIos.from(tag)` — (or add the separate `nfc_manager_ndef` package;
///   we don't, to keep the dependency surface small and the platform
///   differences explicit).
/// * NDEF types (`NdefMessage`, `NdefRecord`, `TypeNameFormat`) come from
///   the `ndef_record` package, re-exported as
///   `package:nfc_manager/ndef_record.dart`.
///
/// ## Platform setup (done in issue 08)
/// * Android: `<uses-permission android:name="android.permission.NFC"/>`
///   (a normal, install-time permission — no runtime prompt) and
///   `<uses-feature android:name="android.hardware.nfc" android:required="false"/>`
///   so phones without NFC can still install the app.
/// * iOS: the "Near Field Communication Tag Reading" capability
///   (entitlement `com.apple.developer.nfc.readersession.formats` = `TAG`,
///   needs a paid developer account) and `NFCReaderUsageDescription` in
///   Info.plist (shown on the scan sheet). iPhone 7+ only; never available
///   in the simulator.
class NfcManagerReader implements NfcReader {
  /// Creates the reader.
  ///
  /// [manager] overrides `NfcManager.instance` (tests); [codec] decodes the
  /// NDEF message; [platform] overrides `defaultTargetPlatform` to pick the
  /// Android vs iOS tag conversion.
  NfcManagerReader({
    NfcManager? manager,
    NdefPairingCodec codec = const NdefPairingCodec(),
    TargetPlatform? platform,
  }) : _managerOverride = manager,
       _codec = codec,
       _platform = platform;

  final NfcManager? _managerOverride;
  final NdefPairingCodec _codec;
  final TargetPlatform? _platform;
  Completer<Result<PairingTag, Failure>>? _pending;

  NfcManager get _manager => _managerOverride ?? NfcManager.instance;
  TargetPlatform get _targetPlatform => _platform ?? defaultTargetPlatform;

  /// Maps the plugin's `NfcAvailability` to [NfcStatus]. Any error (no
  /// plugin on this platform, `MissingPluginException` in a test host,
  /// platform exception) is reported as [NfcStatus.unsupported] instead of
  /// crashing, so the UI just falls back to BLE scanning.
  @override
  Future<NfcStatus> checkAvailability() async {
    try {
      return switch (await _manager.checkAvailability()) {
        NfcAvailability.enabled => NfcStatus.available,
        NfcAvailability.disabled => NfcStatus.disabled,
        NfcAvailability.unsupported => NfcStatus.unsupported,
      };
    } catch (_) {
      return NfcStatus.unsupported;
    }
  }

  /// Polls for ISO 14443 (NFC-A/B: NTAG/MIFARE Ultralight stickers, the
  /// common NDEF tags) and ISO 15693 (NFC-V) tags. ISO 18092 (FeliCa) is
  /// deliberately not requested: on iOS it requires extra
  /// `felica.systemcodes` Info.plist entries or the session fails to start.
  ///
  /// On iOS `alertMessageIos` is the text on the system scan sheet, and
  /// `stopSession(alertMessageIos:/errorMessageIos:)` shows a ✓ or ✗ on it
  /// before it closes. Android has no system UI; our own card shows
  /// progress.
  @override
  Future<Result<PairingTag, Failure>> readPairingTag() async {
    if (_pending != null) {
      return const Err(NfcUnavailable('An NFC read is already in progress'));
    }
    final status = await checkAvailability();
    if (status != NfcStatus.available) {
      return Err(
        NfcUnavailable(
          status == NfcStatus.disabled
              ? 'NFC is turned off in system settings'
              : 'This device cannot read NFC tags',
        ),
      );
    }
    final completer = _pending = Completer<Result<PairingTag, Failure>>();
    try {
      await _manager.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        alertMessageIos: 'Hold your iPhone near the PPG sensor',
        onDiscovered: (tag) => unawaited(_onDiscovered(tag, completer)),
        onSessionErrorIos: (error) =>
            _complete(completer, Err(_mapIosError(error))),
      );
    } catch (e) {
      // iOS: "session_already_exists", missing entitlement, ...
      _pending = null;
      return Err(NfcUnavailable('Could not start NFC session: $e'));
    }
    return completer.future;
  }

  @override
  Future<void> cancel() async {
    final pending = _pending;
    if (pending == null) return;
    _complete(pending, const Err(NfcReadCancelled()));
    await _stopSession();
  }

  Future<void> _onDiscovered(
    NfcTag tag,
    Completer<Result<PairingTag, Failure>> completer,
  ) async {
    Result<PairingTag, Failure> result;
    try {
      result = _codec.decode(await _readNdef(tag));
    } catch (e) {
      // Tag moved away mid-read ("tag was lost"), I/O error, ...
      result = Err(NfcTagInvalid('Could not read tag: $e'));
    }
    if (completer.isCompleted) return;
    _complete(completer, result);
    await _stopSession(
      alert: result.isOk ? 'Sensor found' : null,
      error: result.failureOrNull?.message,
    );
  }

  /// Converts the opaque [tag] with the platform-specific NDEF class.
  /// Both plugins read the NDEF message while discovering the tag and expose
  /// it as `cachedNdefMessage`; reading again is only a fallback. `null`
  /// means the tag is not NDEF formatted.
  Future<NdefMessage?> _readNdef(NfcTag tag) async {
    switch (_targetPlatform) {
      case TargetPlatform.android:
        final ndef = NdefAndroid.from(tag);
        if (ndef == null) return null;
        return ndef.cachedNdefMessage ?? await ndef.getNdefMessage();
      case TargetPlatform.iOS:
        final ndef = NdefIos.from(tag);
        if (ndef == null) return null;
        return ndef.cachedNdefMessage ?? await ndef.readNdef();
      default:
        return null;
    }
  }

  /// iOS invalidates the session itself on cancel/timeout and reports why.
  /// After such an error the session is already gone: don't stop it again.
  static Failure _mapIosError(NfcReaderSessionErrorIos error) =>
      switch (error.code) {
        NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled =>
          const NfcReadCancelled(),
        NfcReaderErrorCodeIos.readerSessionInvalidationErrorSessionTimeout =>
          const NfcReadCancelled('NFC scan timed out'),
        _ => NfcUnavailable('NFC session ended: ${error.message}'),
      };

  void _complete(
    Completer<Result<PairingTag, Failure>> completer,
    Result<PairingTag, Failure> result,
  ) {
    if (identical(_pending, completer)) _pending = null;
    if (!completer.isCompleted) completer.complete(result);
  }

  Future<void> _stopSession({String? alert, String? error}) async {
    try {
      await _manager.stopSession(
        alertMessageIos: alert,
        errorMessageIos: error,
      );
    } catch (_) {
      // Already stopped (iOS throws "no_active_sessions").
    }
  }
}
