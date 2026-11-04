import 'package:get_it/get_it.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart' show Storage;

import '../../features/cloud_sync/data/connectivity_plus_monitor.dart';
import '../../features/cloud_sync/data/disabled_cloud_remote.dart';
import '../../features/cloud_sync/data/drift_cloud_sync_repository.dart';
import '../../features/cloud_sync/data/firebase_cloud_remote.dart';
import '../../features/cloud_sync/domain/cloud_remote.dart';
import '../../features/cloud_sync/domain/cloud_sync_repository.dart';
import '../../features/cloud_sync/domain/connectivity_monitor.dart';
import '../../features/device_connection/data/adapters/ppg_device_adapter.dart';
import '../../features/device_connection/data/adapters/reactive_ble_ppg_device_adapter.dart';
import '../../features/device_connection/data/device_repository_impl.dart';
import '../../features/device_connection/data/fake/fake_permission_service.dart';
import '../../features/device_connection/data/fake/fake_ppg_device.dart';
import '../../features/device_connection/data/permission_handler_service.dart';
import '../../features/device_connection/data/protocol/ppg_packet_codec.dart';
import '../../features/device_connection/domain/device_repository.dart';
import '../../features/device_connection/domain/permission_service.dart';
import '../../features/pairing_nfc/data/fake/fake_nfc_reader.dart';
import '../../features/pairing_nfc/data/nfc_manager_reader.dart';
import '../../features/pairing_nfc/domain/nfc_reader.dart';
import '../../features/ppg_recording/data/drift_recording_repository.dart';
import '../../features/ppg_recording/domain/recording_repository.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../storage/in_memory_storage.dart';

/// Global service locator. Wiring is hand-written (no code generation) so
/// every dependency edge is visible in one file.
final GetIt sl = GetIt.instance;

/// Registers all app-wide singletons. Call once from `main()` before
/// `runApp`; tests can pass a custom [config] and call [sl.reset] after.
///
/// [database] overrides the on-disk database (tests use an in-memory one).
/// [firebaseReady] is the result of `initializeFirebase`; without it cloud
/// sync uses [DisabledCloudRemote] and never touches the Firebase SDKs.
/// [cloudRemote] / [connectivity] override the backend and network monitor.
/// [hydratedStorage] is where `HydratedBloc`s (the NFC pairing bloc)
/// persist state: `main()` passes the on-disk `HydratedStorage`; when
/// omitted (tests) an [InMemoryStorage] is used.
Future<void> configureDependencies(
  AppConfig config, {
  AppDatabase? database,
  Storage? hydratedStorage,
  bool firebaseReady = false,
  CloudRemote? cloudRemote,
  ConnectivityMonitor? connectivity,
}) async {
  sl
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<PpgPacketCodec>(const PpgPacketCodec());

  // The DI flag that swaps the radio: everything above the adapter is
  // identical for fake and real hardware.
  if (config.useFakeDevice) {
    final fake = FakePpgDevice(codec: sl());
    sl
      ..registerSingleton<FakePpgDevice>(fake, dispose: (d) => d.dispose())
      ..registerSingleton<PpgDeviceAdapter>(fake)
      // Simulators have no Bluetooth permission prompt; the fake grants.
      ..registerSingleton<PermissionService>(FakePermissionService());
  } else {
    // Real radio via flutter_reactive_ble; runtime permissions through
    // permission_handler (Android 12+ nearby-devices, Android <= 11
    // location, iOS CoreBluetooth authorization).
    sl
      ..registerSingleton<PpgDeviceAdapter>(
        ReactiveBlePpgDeviceAdapter(),
        dispose: (a) => (a as ReactiveBlePpgDeviceAdapter).dispose(),
      )
      ..registerSingleton<PermissionService>(PermissionHandlerService());
  }

  // USE_FAKE_NFC: simulators have no NFC reader; the fake "taps" the
  // simulated sensor's tag.
  if (config.useFakeNfc) {
    sl.registerSingleton<NfcReader>(
      FakeNfcReader(
        deviceId: FakePpgDevice.defaultDeviceId,
        deviceName: 'PPG-Fake-0001',
      ),
      dispose: (r) => (r as FakeNfcReader).dispose(),
    );
  } else {
    sl.registerSingleton<NfcReader>(NfcManagerReader());
  }

  sl
    ..registerSingleton<Storage>(hydratedStorage ?? InMemoryStorage())
    ..registerLazySingleton<DeviceRepository>(
      () => DeviceRepositoryImpl(adapter: sl(), codec: sl()),
    )
    ..registerSingleton<AppDatabase>(
      database ?? AppDatabase.open(),
      dispose: (db) => db.close(),
    )
    ..registerLazySingleton<RecordingRepository>(
      () => DriftRecordingRepository(sl()),
    )
    ..registerSingleton<CloudRemote>(
      cloudRemote ??
          (firebaseReady
              ? FirebaseCloudRemote()
              : DisabledCloudRemote(
                  config.enableFirebase
                      ? 'Cloud sync disabled (Firebase failed to initialize)'
                      : 'Cloud sync disabled (ENABLE_FIREBASE=false)',
                )),
    )
    // Without Firebase there is nothing to resume on reconnect, and tests
    // must not touch the connectivity_plus platform channel.
    ..registerSingleton<ConnectivityMonitor>(
      connectivity ??
          (firebaseReady
              ? ConnectivityPlusMonitor()
              : const StaticConnectivityMonitor()),
    )
    ..registerLazySingleton<CloudSyncRepository>(
      () => DriftCloudSyncRepository(sl(), sl()),
    );
}
