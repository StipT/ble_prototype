/// Compile-time configuration, read from `--dart-define` flags.
///
/// ```sh
/// flutter run --dart-define=USE_FAKE_DEVICE=false --dart-define=USE_EMULATOR=true
/// ```
class AppConfig {
  /// Creates a config; tests can pass explicit values.
  const AppConfig({
    this.useFakeDevice = true,
    this.useFakeNfc = true,
    this.useEmulator = false,
    this.enableFirebase = true,
    this.emulatorHost = 'localhost',
  });

  /// Reads `USE_FAKE_DEVICE` (default `true`), `USE_FAKE_NFC` (default `true`),
  /// `USE_EMULATOR` (default `false`), `ENABLE_FIREBASE` (default `true`) and
  /// `EMULATOR_HOST` (default `localhost`; use `10.0.2.2` for the Android
  /// emulator talking to the host machine).
  factory AppConfig.fromEnvironment() => const AppConfig(
    useFakeDevice: bool.fromEnvironment('USE_FAKE_DEVICE', defaultValue: true),
    useFakeNfc: bool.fromEnvironment('USE_FAKE_NFC', defaultValue: true),
    useEmulator: bool.fromEnvironment('USE_EMULATOR'),
    enableFirebase: bool.fromEnvironment('ENABLE_FIREBASE', defaultValue: true),
    emulatorHost: String.fromEnvironment(
      'EMULATOR_HOST',
      defaultValue: 'localhost',
    ),
  );

  /// Use `FakePpgDevice` instead of the real `flutter_reactive_ble` adapter.
  final bool useFakeDevice;

  /// Use the fake NFC reader instead of the platform plugin.
  final bool useFakeNfc;

  /// Point Firebase SDKs at the local emulator suite.
  final bool useEmulator;

  /// Whether to initialize Firebase at all (cloud sync is disabled otherwise).
  final bool enableFirebase;

  /// Host where the Firebase emulators listen.
  final String emulatorHost;
}
