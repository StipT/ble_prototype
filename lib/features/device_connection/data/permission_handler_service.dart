import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/permission_service.dart';

/// [PermissionService] backed by the `permission_handler` plugin.
///
/// Which OS permissions are involved depends on the platform:
/// * **Android**: `Permission.bluetoothScan` + `Permission.bluetoothConnect`.
///   On Android 11 (API 30) and lower these runtime permissions don't exist
///   (the legacy install-time `BLUETOOTH` / `BLUETOOTH_ADMIN` cover them),
///   but BLE *scanning* needs `ACCESS_FINE_LOCATION` because scan results
///   can reveal the user's position. The service therefore asks for
///   `Permission.locationWhenInUse` instead on API ≤ 30. The manifest
///   declares location with `maxSdkVersion="30"`, so on Android 12+ it is
///   not even requestable — `BLUETOOTH_SCAN` is declared
///   `neverForLocation` instead. The OS location toggle must also be on
///   (reported by the adapter as "Bluetooth off"-like status).
/// * **iOS**: `Permission.bluetooth` (CoreBluetooth authorization). iOS
///   never shows the dialog twice, so a denial is effectively permanent and
///   the plugin reports it as `permanentlyDenied`.
class PermissionHandlerService implements PermissionService {
  /// [platform] overrides `defaultTargetPlatform` (useful in tests).
  /// [androidSdkInt] reports the Android API level (defaults to
  /// `device_info_plus`); it is only called on Android and cached.
  PermissionHandlerService({
    TargetPlatform? platform,
    Future<int> Function()? androidSdkInt,
  }) : _platform = platform ?? defaultTargetPlatform,
       _androidSdkInt = androidSdkInt ?? _deviceSdkInt;

  final TargetPlatform _platform;
  final Future<int> Function() _androidSdkInt;
  int? _sdkInt;

  static Future<int> _deviceSdkInt() async =>
      (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  /// The runtime permissions BLE needs on this OS version.
  @visibleForTesting
  Future<List<Permission>> requiredPermissions() async {
    if (_platform != TargetPlatform.android) return [Permission.bluetooth];
    final sdk = _sdkInt ??= await _androidSdkInt();
    return sdk <= 30
        ? [Permission.locationWhenInUse]
        : [Permission.bluetoothScan, Permission.bluetoothConnect];
  }

  @override
  Future<BlePermissionStatus> check() async {
    final statuses = [
      for (final p in await requiredPermissions()) await p.status,
    ];
    return _combine(statuses);
  }

  @override
  Future<BlePermissionStatus> request() async {
    // Requesting a list shows one combined dialog on Android 12+
    // ("Allow app to find, connect to and determine the relative position
    // of nearby devices?") instead of two separate prompts.
    final result = await (await requiredPermissions()).request();
    return _combine(result.values);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  /// The most restrictive status wins: one permanently denied permission
  /// blocks BLE as much as all of them being denied.
  static BlePermissionStatus _combine(Iterable<PermissionStatus> statuses) {
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return BlePermissionStatus.permanentlyDenied;
    }
    if (statuses.every((s) => s.isGranted || s.isLimited)) {
      return BlePermissionStatus.granted;
    }
    return BlePermissionStatus.denied;
  }
}
