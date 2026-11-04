import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import 'entities/pairing_tag.dart';

/// Whether this phone can read NFC tags right now.
enum NfcStatus {
  /// NFC hardware present, switched on, and the app may use it.
  available,

  /// Hardware present but switched off by the user (Android Settings →
  /// Connected devices → NFC). iOS has no user-facing NFC switch, so this
  /// only happens on Android. The app cannot turn it on itself.
  disabled,

  /// No NFC reader (most tablets, all simulators/emulators, desktop), or the
  /// OS forbids access — e.g. iOS without the
  /// `com.apple.developer.nfc.readersession.formats` entitlement, or iPhones
  /// older than the 7.
  unsupported,
}

/// Reads one pairing tag. The single seam between the pairing feature and
/// the NFC hardware: `NfcManagerReader` talks to the `nfc_manager` plugin,
/// `FakeNfcReader` simulates a tap for simulators (`USE_FAKE_NFC=true`) and
/// tests.
///
/// ## NFC in 60 seconds
/// * **Tag**: a passive chip + antenna. The phone's reader field powers it
///   and exchanges commands with it at a few cm range. Tags come in several
///   radio/command families: ISO 14443 (NFC-A/B, e.g. NTAG21x stickers,
///   MIFARE), ISO 15693 (NFC-V, "vicinity" tags), ISO 18092 (FeliCa).
/// * **NDEF** (NFC Data Exchange Format): the NFC Forum's standard way to
///   store data on *any* of those tag families. An NDEF **message** is a list
///   of **records**; each record has a **TNF** (Type Name Format: how to
///   interpret the type field — well-known, MIME media, absolute URI,
///   external, ...), a **type** (e.g. `U` = URI, `T` = text), an optional
///   id, and a **payload**. We only need NDEF, never raw tag commands.
/// * **Session**: the app must explicitly start polling for tags and stop
///   again. On **Android** the session is invisible: while it is active and
///   the app is in the foreground, tags are delivered to it (foreground
///   reader mode) and the system's tag dispatch is suppressed. On **iOS**
///   starting a session shows a system sheet ("Ready to Scan"), the session
///   times out after 60 s, the user can cancel it, and only one session may
///   exist at a time. iOS cannot read tags in the background for third-party
///   apps except via NDEF URL "background tag reading" (which launches the
///   app through a universal link, not this API).
abstract interface class NfcReader {
  /// Reports whether a read can start. Cheap; call it on page load to decide
  /// between showing "Tap to pair" and falling back to BLE scanning.
  Future<NfcStatus> checkAvailability();

  /// Starts an NFC session, waits for the user to hold the phone to a tag,
  /// decodes its NDEF message, and stops the session.
  ///
  /// Completes with:
  /// * `Ok(PairingTag)` for a valid pairing tag;
  /// * `Err(NfcUnavailable)` if NFC is off/unsupported or the session could
  ///   not start (e.g. another iOS session is active);
  /// * `Err(NfcTagInvalid)` if a tag was read but carries no pairing record;
  /// * `Err(NfcReadCancelled)` after [cancel], a user cancel on the iOS
  ///   sheet, or the iOS 60 s session timeout.
  ///
  /// Only one read may be in flight; a second call while one is pending
  /// returns `Err(NfcUnavailable)`.
  Future<Result<PairingTag, Failure>> readPairingTag();

  /// Stops a pending [readPairingTag] (which then completes with
  /// `NfcReadCancelled`). No-op when nothing is pending. Always stop the
  /// session when leaving the screen: on Android an open reader-mode
  /// session keeps the NFC field on and drains battery.
  Future<void> cancel();
}
