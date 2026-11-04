import 'package:equatable/equatable.dart';

/// The information an NFC pairing tag carries: which BLE peripheral to
/// connect to.
///
/// ## Why NFC for pairing?
/// BLE scanning shows every advertising device nearby; picking "yours" from
/// a list of identical `PPG-Sensor` entries is error-prone. NFC (Near Field
/// Communication, 13.56 MHz) only works at ~1–4 cm, so physically touching
/// the phone to the sensor's tag is an unambiguous "this one". The tag is a
/// passive sticker with no battery: the phone's field powers it while it
/// answers. NFC does not replace BLE here — it only transports the
/// identifier; the data link is still BLE.
///
/// The on-tag encoding lives in `NdefPairingCodec` (data layer); this class
/// is the decoded, platform-independent result.
final class PairingTag extends Equatable {
  /// Creates a tag payload.
  ///
  /// [deviceId] is the BLE identifier to connect to: on Android the
  /// peripheral's MAC address (`AA:BB:CC:DD:EE:FF`); on iOS CoreBluetooth
  /// never exposes MACs and instead assigns each peripheral a random,
  /// per-phone UUID — so a tag written with a MAC only matches directly on
  /// Android. [deviceName] is the optional human-readable advertised name,
  /// shown in the UI and usable to find the device by name on iOS.
  const PairingTag({required this.deviceId, this.deviceName});

  /// BLE identifier (MAC on Android, CoreBluetooth UUID on iOS), normalized
  /// to upper case.
  final String deviceId;

  /// Advertised name, if the tag carries one.
  final String? deviceName;

  @override
  List<Object?> get props => [deviceId, deviceName];
}
