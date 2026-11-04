/// Outcome of asking the OS for the Bluetooth runtime permissions.
///
/// BLE needs *runtime* permissions on both platforms, but they differ:
/// * **Android 12+ (API 31+)**: `BLUETOOTH_SCAN` (to discover advertisers)
///   and `BLUETOOTH_CONNECT` (to open a GATT connection and read names).
///   Declaring `BLUETOOTH_SCAN` with `android:usesPermissionFlags=
///   "neverForLocation"` means no location permission is needed.
/// * **Android <= 11 (API <= 30)**: scanning is treated as a location
///   capability, so `ACCESS_FINE_LOCATION` must be granted and the location
///   service switched on, otherwise scans silently return nothing.
/// * **iOS**: one permission (`CBManagerAuthorization`), prompted by the OS
///   the first time the app touches CoreBluetooth. The Info.plist must
///   contain `NSBluetoothAlwaysUsageDescription` or the app crashes.
enum BlePermissionStatus {
  /// Everything needed to scan and connect is granted.
  granted,

  /// Refused, but the app may show the system dialog again.
  denied,

  /// Refused with "don't ask again" (Android) or refused once (iOS, which
  /// never re-prompts), or blocked by parental controls / MDM ("restricted").
  /// Only the Settings app can change it now.
  permanentlyDenied,
}

/// Abstraction over the platform permission APIs, so blocs stay testable and
/// the fake device mode works on simulators without real prompts.
///
/// Implemented by `PermissionHandlerService` (package `permission_handler`)
/// and `FakePermissionService` (in-memory, for tests and fake-device mode).
abstract interface class PermissionService {
  /// Reads the current status **without** showing any dialog. Safe to call
  /// at start-up and every time the app returns to the foreground (the user
  /// may have changed the permission in Settings meanwhile).
  Future<BlePermissionStatus> check();

  /// Shows the system permission dialog(s) if the OS still allows it and
  /// returns the resulting status. When the status is already
  /// [BlePermissionStatus.permanentlyDenied] the OS shows nothing and this
  /// returns immediately — call [openSettings] instead.
  Future<BlePermissionStatus> request();

  /// Opens this app's page in the OS Settings app (the only way out of
  /// [BlePermissionStatus.permanentlyDenied]). Returns `false` if the
  /// settings screen could not be opened.
  Future<bool> openSettings();
}
