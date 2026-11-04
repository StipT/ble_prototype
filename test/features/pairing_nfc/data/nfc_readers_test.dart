import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/features/pairing_nfc/data/fake/fake_nfc_reader.dart';
import 'package:ble_prototype/features/pairing_nfc/data/nfc_manager_reader.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/entities/pairing_tag.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/nfc_reader.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

class _MockNfcManager extends Mock implements NfcManager {}

void main() {
  group('FakeNfcReader', () {
    test('reads the simulated tag after tapDelay', () {
      fakeAsync((async) {
        final reader = FakeNfcReader(
          deviceId: 'FA:KE:00:00:00:01',
          deviceName: 'PPG-Fake-0001',
          tapDelay: const Duration(seconds: 1),
        );
        Object? result;
        reader.readPairingTag().then((r) => result = r);
        async.elapse(const Duration(milliseconds: 999));
        expect(result, isNull);
        expect(reader.isReading, isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          (result! as dynamic).valueOrNull,
          const PairingTag(
            deviceId: 'FA:KE:00:00:00:01',
            deviceName: 'PPG-Fake-0001',
          ),
        );
        expect(reader.isReading, isFalse);
      });
    });

    test('cancel completes with NfcReadCancelled', () async {
      final reader = FakeNfcReader(deviceId: 'FA:KE:00:00:00:01');
      final future = reader.readPairingTag();
      await reader.cancel();
      expect((await future).failureOrNull, isA<NfcReadCancelled>());
    });

    test('unavailable status → NfcUnavailable without reading', () async {
      final reader = FakeNfcReader(
        deviceId: 'FA:KE:00:00:00:01',
        status: NfcStatus.disabled,
      );
      expect(await reader.checkAvailability(), NfcStatus.disabled);
      expect(
        (await reader.readPairingTag()).failureOrNull,
        isA<NfcUnavailable>(),
      );
      expect(reader.readCount, 0);
    });

    test('non-NDEF tag → NfcTagInvalid', () async {
      final reader = FakeNfcReader(deviceId: 'FA:KE:00:00:00:01')
        ..nextMessage = null;
      final future = reader.readPairingTag();
      reader.tapNow();
      expect((await future).failureOrNull, isA<NfcTagInvalid>());
    });

    test('second concurrent read is rejected', () async {
      final reader = FakeNfcReader(deviceId: 'FA:KE:00:00:00:01');
      final first = reader.readPairingTag();
      expect(
        (await reader.readPairingTag()).failureOrNull,
        isA<NfcUnavailable>(),
      );
      reader.dispose();
      expect((await first).failureOrNull, isA<NfcReadCancelled>());
    });
  });

  group('NfcManagerReader', () {
    late _MockNfcManager manager;
    late NfcManagerReader reader;

    setUp(() {
      manager = _MockNfcManager();
      reader = NfcManagerReader(manager: manager, platform: TargetPlatform.iOS);
      when(
        () => manager.stopSession(
          alertMessageIos: any(named: 'alertMessageIos'),
          errorMessageIos: any(named: 'errorMessageIos'),
        ),
      ).thenAnswer((_) async {});
    });

    void stubAvailability(NfcAvailability a) =>
        when(manager.checkAvailability).thenAnswer((_) async => a);

    // Captures the callbacks passed to startSession.
    ({
      void Function(NfcTag) onDiscovered,
      void Function(NfcReaderSessionErrorIos)? onError,
    })
    captureSession() {
      final captured = verify(
        () => manager.startSession(
          pollingOptions: any(named: 'pollingOptions'),
          onDiscovered: captureAny(named: 'onDiscovered'),
          alertMessageIos: any(named: 'alertMessageIos'),
          onSessionErrorIos: captureAny(named: 'onSessionErrorIos'),
        ),
      ).captured;
      return (
        onDiscovered: captured[0] as void Function(NfcTag),
        onError: captured[1] as void Function(NfcReaderSessionErrorIos)?,
      );
    }

    void stubStart() => when(
      () => manager.startSession(
        pollingOptions: any(named: 'pollingOptions'),
        onDiscovered: any(named: 'onDiscovered'),
        alertMessageIos: any(named: 'alertMessageIos'),
        onSessionErrorIos: any(named: 'onSessionErrorIos'),
      ),
    ).thenAnswer((_) async {});

    test('maps plugin availability', () async {
      for (final (plugin, ours) in [
        (NfcAvailability.enabled, NfcStatus.available),
        (NfcAvailability.disabled, NfcStatus.disabled),
        (NfcAvailability.unsupported, NfcStatus.unsupported),
      ]) {
        stubAvailability(plugin);
        expect(await reader.checkAvailability(), ours);
      }
    });

    test('plugin errors are reported as unsupported', () async {
      when(manager.checkAvailability).thenThrow(UnsupportedError('desktop'));
      expect(await reader.checkAvailability(), NfcStatus.unsupported);
    });

    test('disabled NFC → NfcUnavailable, no session started', () async {
      stubAvailability(NfcAvailability.disabled);
      final r = await reader.readPairingTag();
      expect(r.failureOrNull, isA<NfcUnavailable>());
      verifyNever(
        () => manager.startSession(
          pollingOptions: any(named: 'pollingOptions'),
          onDiscovered: any(named: 'onDiscovered'),
        ),
      );
    });

    test('startSession failure → NfcUnavailable', () async {
      stubAvailability(NfcAvailability.enabled);
      when(
        () => manager.startSession(
          pollingOptions: any(named: 'pollingOptions'),
          onDiscovered: any(named: 'onDiscovered'),
          alertMessageIos: any(named: 'alertMessageIos'),
          onSessionErrorIos: any(named: 'onSessionErrorIos'),
        ),
      ).thenThrow(Exception('session_already_exists'));
      expect(
        (await reader.readPairingTag()).failureOrNull,
        isA<NfcUnavailable>(),
      );
    });

    test('iOS user cancel → NfcReadCancelled', () async {
      stubAvailability(NfcAvailability.enabled);
      stubStart();
      final future = reader.readPairingTag();
      await Future<void>.delayed(Duration.zero);
      captureSession().onError!(
        const NfcReaderSessionErrorIos(
          code:
              NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled,
          message: 'cancelled',
        ),
      );
      expect((await future).failureOrNull, isA<NfcReadCancelled>());
    });

    test('cancel() stops the session', () async {
      stubAvailability(NfcAvailability.enabled);
      stubStart();
      final future = reader.readPairingTag();
      await Future<void>.delayed(Duration.zero);
      await reader.cancel();
      expect((await future).failureOrNull, isA<NfcReadCancelled>());
      verify(
        () => manager.stopSession(
          alertMessageIos: any(named: 'alertMessageIos'),
          errorMessageIos: any(named: 'errorMessageIos'),
        ),
      ).called(1);
    });

    test('unreadable tag → NfcTagInvalid and session stopped', () async {
      stubAvailability(NfcAvailability.enabled);
      stubStart();
      final future = reader.readPairingTag();
      await Future<void>.delayed(Duration.zero);
      // Not a platform tag object: conversion fails like a lost tag would.
      // ignore: invalid_use_of_visible_for_testing_member
      captureSession().onDiscovered(const NfcTag(data: 'garbage'));
      expect((await future).failureOrNull, isA<NfcTagInvalid>());
      await Future<void>.delayed(Duration.zero);
      verify(
        () => manager.stopSession(
          alertMessageIos: any(named: 'alertMessageIos'),
          errorMessageIos: any(named: 'errorMessageIos'),
        ),
      ).called(1);
    });
  });
}
