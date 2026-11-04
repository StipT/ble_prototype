import 'dart:convert';
import 'dart:typed_data';

import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/result/result.dart';
import 'package:ble_prototype/features/pairing_nfc/data/ndef_pairing_codec.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/entities/pairing_tag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';

NdefRecord _wellKnown(String type, List<int> payload) => NdefRecord(
  typeNameFormat: TypeNameFormat.wellKnown,
  type: Uint8List.fromList(type.codeUnits),
  identifier: Uint8List(0),
  payload: Uint8List.fromList(payload),
);

NdefRecord _uri(String uri, {int prefix = 0}) =>
    _wellKnown('U', [prefix, ...utf8.encode(uri)]);

NdefRecord _text(String text, {String lang = 'en'}) =>
    _wellKnown('T', [lang.length, ...ascii.encode(lang), ...utf8.encode(text)]);

NdefMessage _msg(List<NdefRecord> records) => NdefMessage(records: records);

Failure? _failure(Result<PairingTag, Failure> r) => r.failureOrNull;

void main() {
  const codec = NdefPairingCodec();

  group('decode valid tags', () {
    test('URI record with id and name', () {
      final r = codec.decode(
        _msg([_uri('ppgsync://pair?id=aa:bb:cc:dd:ee:ff&name=PPG-Sensor')]),
      );
      expect(
        r,
        const Ok<PairingTag, Failure>(
          PairingTag(deviceId: 'AA:BB:CC:DD:EE:FF', deviceName: 'PPG-Sensor'),
        ),
      );
    });

    test('URI record without name; iOS UUID id is accepted', () {
      final r = codec.decode(
        _msg([_uri('ppgsync://pair?id=12345678-9abc-def0-1234-56789abcdef0')]),
      );
      expect(
        r.valueOrNull,
        const PairingTag(deviceId: '12345678-9ABC-DEF0-1234-56789ABCDEF0'),
      );
    });

    test('Text record with a bare id (UTF-8)', () {
      final r = codec.decode(_msg([_text(' FA:KE:00:00:00:01 ')]));
      expect(r.valueOrNull?.deviceId, 'FA:KE:00:00:00:01');
    });

    test('Text record with UTF-16 encoding (BOM, little-endian)', () {
      final units = 'ppgsync://pair?id=AA:BB:CC:DD:EE:01'.codeUnits;
      final bytes = [
        0xFF,
        0xFE,
        for (final u in units) ...[u & 0xFF, u >> 8],
      ];
      final r = codec.decode(
        _msg([
          _wellKnown('T', [0x80 | 2, ...ascii.encode('en'), ...bytes]),
        ]),
      );
      expect(r.valueOrNull?.deviceId, 'AA:BB:CC:DD:EE:01');
    });

    test('absolute-URI TNF record', () {
      final record = NdefRecord(
        typeNameFormat: TypeNameFormat.absoluteUri,
        type: Uint8List.fromList(
          utf8.encode('ppgsync://pair?id=AA:BB:CC:DD:EE:02'),
        ),
        identifier: Uint8List(0),
        payload: Uint8List(0),
      );
      expect(
        codec.decode(_msg([record])).valueOrNull?.deviceId,
        'AA:BB:CC:DD:EE:02',
      );
    });

    test('skips unrelated records before the pairing record', () {
      final r = codec.decode(
        _msg([
          _uri('example.com', prefix: 0x04), // https://example.com
          NdefRecord(
            typeNameFormat: TypeNameFormat.external,
            type: Uint8List.fromList('android.com:pkg'.codeUnits),
            identifier: Uint8List(0),
            payload: Uint8List.fromList('com.example'.codeUnits),
          ),
          _uri('ppgsync://pair?id=AA:BB:CC:DD:EE:03'),
        ]),
      );
      expect(r.valueOrNull?.deviceId, 'AA:BB:CC:DD:EE:03');
    });

    test('encode → decode round-trip', () {
      const tag = PairingTag(
        deviceId: 'FA:KE:00:00:00:01',
        deviceName: 'PPG Fake & Co',
      );
      expect(codec.decode(codec.encode(tag)).valueOrNull, tag);
    });
  });

  group('decode malformed tags → NfcTagInvalid', () {
    test('not NDEF formatted (null message)', () {
      expect(_failure(codec.decode(null)), isA<NfcTagInvalid>());
    });

    test('empty message', () {
      expect(_failure(codec.decode(_msg([]))), isA<NfcTagInvalid>());
    });

    test('only foreign records', () {
      final f = _failure(
        codec.decode(_msg([_uri('example.com', prefix: 0x04)])),
      );
      expect(f, const NfcTagInvalid('No pairing record on tag'));
    });

    test('pairing URI with invalid id is reported over foreign records', () {
      final f = _failure(
        codec.decode(
          _msg([
            _uri('example.com', prefix: 0x04),
            _uri('ppgsync://pair?id=not-a-mac'),
          ]),
        ),
      );
      expect(f, const NfcTagInvalid('Invalid device id "not-a-mac"'));
    });

    test('pairing URI without id', () {
      expect(
        _failure(codec.decode(_msg([_uri('ppgsync://pair?name=x')]))),
        const NfcTagInvalid('Pairing URI has no device id'),
      );
    });

    test('unknown pairing action', () {
      expect(
        _failure(
          codec.decode(_msg([_uri('ppgsync://unpair?id=AA:BB:CC:DD:EE:FF')])),
        ),
        isA<NfcTagInvalid>(),
      );
    });

    test('empty URI payload', () {
      expect(
        _failure(codec.decode(_msg([_wellKnown('U', [])]))),
        isA<NfcTagInvalid>(),
      );
    });

    test('invalid UTF-8 in URI payload', () {
      expect(
        _failure(
          codec.decode(
            _msg([
              _wellKnown('U', [0, 0xC3, 0x28]),
            ]),
          ),
        ),
        isA<NfcTagInvalid>(),
      );
    });

    test('Text record whose language length overruns the payload', () {
      expect(
        _failure(
          codec.decode(
            _msg([
              _wellKnown('T', [0x3F, 0x65]),
            ]),
          ),
        ),
        isA<NfcTagInvalid>(),
      );
    });

    test('Text record with odd-length UTF-16', () {
      expect(
        _failure(
          codec.decode(
            _msg([
              _wellKnown('T', [0x80, 0x00, 0x41, 0x00]),
            ]),
          ),
        ),
        isA<NfcTagInvalid>(),
      );
    });

    test('Text record with garbage text', () {
      expect(
        _failure(codec.decode(_msg([_text('hello world')]))),
        isA<NfcTagInvalid>(),
      );
    });
  });

  group('normalizeDeviceId', () {
    test('accepts MAC and UUID, upper-cases', () {
      expect(
        NdefPairingCodec.normalizeDeviceId('aa:bb:cc:dd:ee:ff'),
        'AA:BB:CC:DD:EE:FF',
      );
      expect(
        NdefPairingCodec.normalizeDeviceId(
          '12345678-9ABC-DEF0-1234-56789ABCDEF0',
        ),
        isNotNull,
      );
    });

    test('rejects other strings', () {
      for (final raw in [
        '',
        'AA:BB:CC',
        'AA-BB-CC-DD-EE-FF',
        'AA:BB:CC:DD:EE:FF:00',
      ]) {
        expect(NdefPairingCodec.normalizeDeviceId(raw), isNull, reason: raw);
      }
    });
  });
}
