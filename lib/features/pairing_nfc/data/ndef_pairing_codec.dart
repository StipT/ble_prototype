import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/ndef_record.dart';

import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../domain/entities/pairing_tag.dart';

/// Encodes/decodes [PairingTag]s to/from NDEF messages. Pure Dart (no
/// platform channel), so it is fully unit-testable and shared by the real
/// and the fake reader.
///
/// ## On-tag format
/// Preferred: one **URI record** (TNF = well-known, type = `U`) holding
///
/// ```text
/// ppgsync://pair?id=AA:BB:CC:DD:EE:FF&name=PPG-Sensor
/// ```
///
/// Why a URI rather than a custom binary record: any off-the-shelf NFC
/// writer app (e.g. "NFC Tools") can write it, it is human-readable when
/// debugging, and on Android an `<intent-filter>` for the `ppgsync` scheme
/// could later launch the app on tap even when it is closed.
///
/// Also accepted, for quick hand-made tags:
/// * a URI record of TNF *absolute URI* (the URI sits in the type field);
/// * a well-known **Text record** (type `T`) containing either the URI
///   above or just the bare device ID.
///
/// The first record that decodes wins; unrelated records (a vendor URL, an
/// Android Application Record) are skipped.
///
/// ## Byte layouts (NFC Forum RTDs)
/// * URI record payload: `[prefixCode][utf8 rest]`. The 1-byte prefix code
///   abbreviates common schemes to save tag memory (0x01 = `http://www.`,
///   0x04 = `https://`, ...); 0x00 means "no prefix" — what we use for the
///   custom `ppgsync://` scheme.
/// * Text record payload: `[status][lang code][text]`; status bit 7 = text
///   encoding (0 UTF-8, 1 UTF-16), bits 5..0 = length of the IANA language
///   code (e.g. `en`).
class NdefPairingCodec {
  /// Creates the (stateless) codec.
  const NdefPairingCodec();

  /// Custom URI scheme identifying our pairing URIs.
  static const scheme = 'ppgsync';

  /// URI host ("path") of the pairing action.
  static const host = 'pair';

  // NFC Forum URI RTD abbreviation table, indexed by prefix code.
  static const _uriPrefixes = [
    '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', //
    'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://',
    'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://',
    'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:', 'tftp:', 'btspp://',
    'btl2cap://', 'btgoep://', 'tcpobex://', 'irdaobex://', 'file://',
    'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:',
    'urn:epc:', 'urn:nfc:',
  ];

  static const _notOurs = NfcTagInvalid('Not a pairing record');

  static final _mac = RegExp(r'^([0-9A-Z]{2}:){5}[0-9A-Z]{2}$');
  static final _uuid = RegExp(
    r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
  );

  /// Normalizes and validates a BLE identifier from a tag.
  ///
  /// Accepts a MAC-style address (six `:`-separated pairs, as Android's
  /// `BluetoothDevice.getAddress()` returns — alphanumeric rather than
  /// strictly hex so the simulator's `FA:KE:00:00:00:01` is valid) or an
  /// iOS CoreBluetooth UUID (`8-4-4-4-12` hex). Returns the upper-cased ID,
  /// or `null` when [raw] is neither.
  static String? normalizeDeviceId(String raw) {
    final id = raw.trim().toUpperCase();
    return _mac.hasMatch(id) || _uuid.hasMatch(id) ? id : null;
  }

  /// Decodes the first pairing record in [message].
  ///
  /// Returns `Err(NfcTagInvalid)` when the message is `null` (tag not NDEF
  /// formatted), empty, or contains no record that decodes to a valid
  /// [PairingTag]. Never throws, whatever bytes the tag contains.
  Result<PairingTag, Failure> decode(NdefMessage? message) {
    if (message == null) {
      return const Err(NfcTagInvalid('Tag is not NDEF formatted'));
    }
    if (message.records.isEmpty) {
      return const Err(NfcTagInvalid('Tag is empty'));
    }
    // Report "our record, but malformed" in preference to "not ours".
    Failure? firstError;
    for (final record in message.records) {
      final result = decodeRecord(record);
      switch (result) {
        case Ok():
          return result;
        case Err(:final failure) when failure != _notOurs:
          firstError ??= failure;
        case Err():
          break;
      }
    }
    return Err(firstError ?? const NfcTagInvalid('No pairing record on tag'));
  }

  /// Decodes a single [record]: `Ok` for a valid pairing record, otherwise
  /// `Err(NfcTagInvalid)` — "Not a pairing record" for unrelated records
  /// (other TNF/type, foreign URI), a specific message when the record is
  /// ours but malformed (bad device ID, truncated bytes, invalid UTF-8).
  Result<PairingTag, Failure> decodeRecord(NdefRecord record) {
    try {
      final text = switch (record.typeNameFormat) {
        TypeNameFormat.wellKnown when _typeIs(record, 'U') => _decodeUri(
          record.payload,
        ),
        TypeNameFormat.wellKnown when _typeIs(record, 'T') => _decodeText(
          record.payload,
        ),
        TypeNameFormat.absoluteUri => utf8.decode(record.type),
        _ => null,
      };
      if (text == null) {
        return const Err(_notOurs);
      }
      return _parse(text, bareIdAllowed: _typeIs(record, 'T'));
    } on FormatException catch (e) {
      return Err(NfcTagInvalid('Malformed NDEF record: ${e.message}'));
    } on RangeError {
      return const Err(NfcTagInvalid('Truncated NDEF record'));
    }
  }

  /// Builds the NDEF message to write onto a tag for [tag] (one URI record,
  /// prefix code 0x00). Used by the fake reader and handy for a future
  /// "write tag" debug action.
  NdefMessage encode(PairingTag tag) {
    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: {
        'id': tag.deviceId,
        if (tag.deviceName case final name?) 'name': name,
      },
    ).toString();
    return NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.wellKnown,
          type: Uint8List.fromList('U'.codeUnits),
          identifier: Uint8List(0),
          payload: Uint8List.fromList([0x00, ...utf8.encode(uri)]),
        ),
      ],
    );
  }

  static bool _typeIs(NdefRecord record, String type) =>
      record.type.length == type.length &&
      String.fromCharCodes(record.type) == type;

  static String _decodeUri(Uint8List payload) {
    if (payload.isEmpty) throw const FormatException('empty URI record');
    final code = payload[0];
    // Codes above the table are "reserved for future use": no prefix.
    final prefix = code < _uriPrefixes.length ? _uriPrefixes[code] : '';
    return prefix + utf8.decode(payload.sublist(1));
  }

  static String _decodeText(Uint8List payload) {
    if (payload.isEmpty) throw const FormatException('empty Text record');
    final status = payload[0];
    final isUtf16 = status & 0x80 != 0;
    final langLength = status & 0x3F;
    final body = payload.sublist(1 + langLength);
    return isUtf16 ? _decodeUtf16(body) : utf8.decode(body);
  }

  // UTF-16 with optional BOM; big-endian when absent (per the Text RTD).
  static String _decodeUtf16(Uint8List bytes) {
    if (bytes.length.isOdd) throw const FormatException('odd UTF-16 length');
    var littleEndian = false;
    var start = 0;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        littleEndian = true;
        start = 2;
      } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        start = 2;
      }
    }
    final units = <int>[
      for (var i = start; i < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
    ];
    return String.fromCharCodes(units);
  }

  Result<PairingTag, Failure> _parse(
    String text, {
    required bool bareIdAllowed,
  }) {
    final trimmed = text.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == scheme) {
      if (uri.host != host) {
        return Err(NfcTagInvalid('Unknown pairing action "${uri.host}"'));
      }
      final rawId = uri.queryParameters['id'];
      if (rawId == null) {
        return const Err(NfcTagInvalid('Pairing URI has no device id'));
      }
      final id = normalizeDeviceId(rawId);
      if (id == null) {
        return Err(NfcTagInvalid('Invalid device id "$rawId"'));
      }
      final name = uri.queryParameters['name']?.trim();
      return Ok(
        PairingTag(
          deviceId: id,
          deviceName: (name == null || name.isEmpty) ? null : name,
        ),
      );
    }
    if (bareIdAllowed) {
      final id = normalizeDeviceId(trimmed);
      if (id != null) return Ok(PairingTag(deviceId: id));
      return Err(NfcTagInvalid('Invalid device id "$trimmed"'));
    }
    return const Err(_notOurs);
  }
}
