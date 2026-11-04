import 'package:equatable/equatable.dart';

import 'pairing_tag.dart';

/// The device remembered after a successful NFC tap, persisted across app
/// restarts by `PairingBloc` (a `HydratedBloc`) so the user can reconnect
/// with one button instead of tapping the tag again.
///
/// Note that "paired" here is an *app-level* notion ("the sensor I use"),
/// not BLE bonding. BLE bonding (exchanging long-term encryption keys,
/// shown in the OS Bluetooth settings) is negotiated by the OS when a
/// characteristic requires encryption; this placeholder protocol doesn't.
final class PairedDevice extends Equatable {
  /// Creates a remembered device.
  ///
  /// [deviceId] is the BLE identifier passed to `connect`, [deviceName] the
  /// optional display name from the tag, [pairedAt] when the tag was read.
  const PairedDevice({
    required this.deviceId,
    required this.pairedAt,
    this.deviceName,
  });

  /// Builds the remembered device from a freshly read [tag] at [pairedAt].
  factory PairedDevice.fromTag(PairingTag tag, DateTime pairedAt) =>
      PairedDevice(
        deviceId: tag.deviceId,
        deviceName: tag.deviceName,
        pairedAt: pairedAt,
      );

  /// Restores a device saved by [toJson]. Throws [FormatException] (or a
  /// `TypeError`) for malformed input; `PairingBloc.fromJson` catches it.
  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    final id = json['deviceId'];
    final pairedAt = json['pairedAt'];
    final name = json['deviceName'];
    if (id is! String || id.isEmpty || pairedAt is! String) {
      throw const FormatException('Invalid PairedDevice JSON');
    }
    return PairedDevice(
      deviceId: id,
      deviceName: name as String?,
      pairedAt: DateTime.parse(pairedAt),
    );
  }

  /// BLE identifier to connect to.
  final String deviceId;

  /// Display name, if the tag carried one.
  final String? deviceName;

  /// When the tag was read.
  final DateTime pairedAt;

  /// Name for the UI, falling back to the ID.
  String get label => deviceName ?? deviceId;

  /// JSON-safe map (only strings) for `HydratedBloc` storage.
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'pairedAt': pairedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [deviceId, deviceName, pairedAt];
}
