import 'package:ble_prototype/core/error/failures.dart';
import 'package:ble_prototype/core/storage/in_memory_storage.dart';
import 'package:ble_prototype/features/pairing_nfc/data/fake/fake_nfc_reader.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/entities/paired_device.dart';
import 'package:ble_prototype/features/pairing_nfc/domain/nfc_reader.dart';
import 'package:ble_prototype/features/pairing_nfc/presentation/bloc/pairing_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'FA:KE:00:00:00:01';
final _now = DateTime.utc(2026, 10, 25, 12);
final _device = PairedDevice(
  deviceId: _id,
  deviceName: 'PPG-Fake-0001',
  pairedAt: _now,
);

void main() {
  late FakeNfcReader reader;
  late InMemoryStorage storage;
  late List<String> connected;

  setUp(() {
    reader = FakeNfcReader(
      deviceId: _id,
      deviceName: 'PPG-Fake-0001',
      tapDelay: const Duration(milliseconds: 10),
    );
    storage = InMemoryStorage();
    connected = [];
  });
  tearDown(() => reader.dispose());

  PairingBloc build() => PairingBloc(
    reader: reader,
    connectDevice: connected.add,
    storage: storage,
    clock: Clock.fixed(_now),
  );

  group('JSON persistence', () {
    test('toJson/fromJson round-trip keeps only lastPaired', () {
      final bloc = build();
      final state = PairingState(
        phase: PairingPhase.waitingForTag,
        nfcStatus: NfcStatus.available,
        lastPaired: _device,
        failure: const NfcTagInvalid('x'),
      );
      final json = bloc.toJson(state)!;
      expect(bloc.fromJson(json), PairingState(lastPaired: _device));
      expect(
        bloc.fromJson(bloc.toJson(const PairingState())!),
        const PairingState(),
      );
      bloc.close();
    });

    test('corrupt JSON falls back to the initial state', () {
      final bloc = build();
      expect(bloc.fromJson({'lastPaired': 42}), isNull);
      expect(
        bloc.fromJson({
          'lastPaired': {'deviceId': _id, 'pairedAt': 'not a date'},
        }),
        isNull,
      );
      bloc.close();
    });

    test('a new bloc restores the device paired by a previous one', () async {
      final first = build();
      first.add(const PairingTapRequested());
      await expectLater(
        first.stream,
        emitsThrough(
          predicate<PairingState>((s) => s.lastPaired?.deviceId == _id),
        ),
      );
      await first.close();

      final second = build();
      expect(second.state.lastPaired, _device);
      expect(second.state.phase, PairingPhase.idle);
      await second.close();
    });
  });

  group('flows', () {
    blocTest<PairingBloc, PairingState>(
      'availability check stores the NFC status',
      build: build,
      act: (b) => b.add(const PairingAvailabilityChecked()),
      expect: () => [const PairingState(nfcStatus: NfcStatus.available)],
    );

    blocTest<PairingBloc, PairingState>(
      'tap → waiting → paired, remembers device and connects',
      build: build,
      act: (b) => b.add(const PairingTapRequested()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const PairingState(phase: PairingPhase.waitingForTag),
        PairingState(nfcStatus: NfcStatus.available, lastPaired: _device),
      ],
      verify: (_) {
        expect(connected, [_id]);
        expect(storage.values.values.single, {'lastPaired': _device.toJson()});
      },
    );

    blocTest<PairingBloc, PairingState>(
      'cancel while waiting returns to idle without error or connect',
      build: () {
        reader.tapDelay = const Duration(hours: 1);
        return build();
      },
      act: (b) async {
        b.add(const PairingTapRequested());
        await Future<void>.delayed(Duration.zero);
        b.add(const PairingTapCancelled());
      },
      expect: () => [
        const PairingState(phase: PairingPhase.waitingForTag),
        const PairingState(),
      ],
      verify: (_) => expect(connected, isEmpty),
    );

    blocTest<PairingBloc, PairingState>(
      'NFC disabled → NfcUnavailable failure + status, nothing connected',
      build: () {
        reader.status = NfcStatus.disabled;
        return build();
      },
      act: (b) => b.add(const PairingTapRequested()),
      expect: () => [
        const PairingState(phase: PairingPhase.waitingForTag),
        const PairingState(
          nfcStatus: NfcStatus.disabled,
          failure: NfcUnavailable('NFC is turned off in system settings'),
        ),
      ],
      verify: (_) => expect(connected, isEmpty),
    );

    blocTest<PairingBloc, PairingState>(
      'NFC unsupported reported by the availability check',
      build: () {
        reader.status = NfcStatus.unsupported;
        return build();
      },
      act: (b) => b.add(const PairingAvailabilityChecked()),
      expect: () => [const PairingState(nfcStatus: NfcStatus.unsupported)],
      verify: (b) => expect(b.state.canUseNfc, isFalse),
    );

    blocTest<PairingBloc, PairingState>(
      'NFC switched back on clears the stale NfcUnavailable',
      build: build,
      seed: () => const PairingState(
        nfcStatus: NfcStatus.disabled,
        failure: NfcUnavailable(),
      ),
      act: (b) => b.add(const PairingAvailabilityChecked()),
      expect: () => [const PairingState(nfcStatus: NfcStatus.available)],
    );

    blocTest<PairingBloc, PairingState>(
      'invalid tag keeps the previous device and shows the failure',
      build: () {
        reader.nextMessage = null;
        return build();
      },
      seed: () => PairingState(lastPaired: _device),
      act: (b) => b.add(const PairingTapRequested()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        PairingState(phase: PairingPhase.waitingForTag, lastPaired: _device),
        PairingState(
          lastPaired: _device,
          failure: const NfcTagInvalid('Tag is not NDEF formatted'),
        ),
      ],
      verify: (_) => expect(connected, isEmpty),
    );

    blocTest<PairingBloc, PairingState>(
      'double tap is dropped while a session is open',
      build: build,
      act: (b) => b
        ..add(const PairingTapRequested())
        ..add(const PairingTapRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        expect(reader.readCount, 1);
        expect(connected, [_id]);
      },
    );

    blocTest<PairingBloc, PairingState>(
      'reconnect connects to the remembered device',
      build: build,
      seed: () => PairingState(lastPaired: _device),
      act: (b) => b.add(const PairingReconnectRequested()),
      expect: () => <PairingState>[],
      verify: (_) => expect(connected, [_id]),
    );

    blocTest<PairingBloc, PairingState>(
      'reconnect without a remembered device does nothing',
      build: build,
      act: (b) => b.add(const PairingReconnectRequested()),
      expect: () => <PairingState>[],
      verify: (_) => expect(connected, isEmpty),
    );

    blocTest<PairingBloc, PairingState>(
      'forget clears the device and the persisted copy',
      build: build,
      seed: () => PairingState(lastPaired: _device),
      act: (b) => b.add(const PairingForgotten()),
      expect: () => [const PairingState()],
      verify: (_) => expect(storage.values.values.single, {'lastPaired': null}),
    );
  });
}
