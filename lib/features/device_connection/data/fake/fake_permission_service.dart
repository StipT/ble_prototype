import '../../domain/permission_service.dart';

/// In-memory [PermissionService] for tests and fake-device mode (simulators
/// have no Bluetooth permission prompt to show).
///
/// It mimics the OS rules: [request] turns [BlePermissionStatus.denied] into
/// [requestOutcome] (the user's simulated answer), but cannot leave
/// [BlePermissionStatus.permanentlyDenied] — just like the real dialog is
/// never shown again. [openSettings] simulates the user flipping the switch
/// in Settings when [settingsGrant] is true.
class FakePermissionService implements PermissionService {
  /// [status] is the initial OS state; [requestOutcome] what the simulated
  /// user answers in the dialog; [settingsGrant] whether a visit to Settings
  /// grants the permission.
  FakePermissionService({
    this.status = BlePermissionStatus.granted,
    this.requestOutcome = BlePermissionStatus.granted,
    this.settingsGrant = true,
  });

  /// Current simulated OS permission state.
  BlePermissionStatus status;

  /// Answer given to the next dialog.
  BlePermissionStatus requestOutcome;

  /// Whether [openSettings] grants the permission.
  bool settingsGrant;

  /// Number of times the dialog was "shown".
  int requestCount = 0;

  /// Number of times Settings was opened.
  int openSettingsCount = 0;

  @override
  Future<BlePermissionStatus> check() async => status;

  @override
  Future<BlePermissionStatus> request() async {
    if (status == BlePermissionStatus.denied) {
      requestCount++;
      status = requestOutcome;
    }
    return status;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount++;
    if (settingsGrant) status = BlePermissionStatus.granted;
    return true;
  }
}
