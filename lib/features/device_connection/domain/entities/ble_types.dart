import 'package:equatable/equatable.dart';

/// State of the phone's Bluetooth radio.
///
/// iOS reports this through `CBManagerState`, Android through
/// `BluetoothAdapter.ACTION_STATE_CHANGED`. Both start in [unknown] until the
/// stack has booted, so never treat [unknown] as "off" — wait for the first
/// definite value instead.
enum BluetoothAdapterStatus {
  /// Not yet determined (BLE stack still starting).
  unknown,

  /// Radio is on and usable.
  poweredOn,

  /// Radio is off; ask the user to enable it.
  poweredOff,

  /// The app lacks the runtime permission to use Bluetooth.
  unauthorized,

  /// Hardware has no BLE support (e.g. iOS simulator).
  unsupported,
}

/// Lifecycle of the GATT link to one device.
enum DeviceLinkState {
  /// No link.
  disconnected,

  /// Link-layer connection in progress (and service discovery right after).
  connecting,

  /// Link up, services discovered, notifications enabled.
  connected,

  /// Graceful disconnect requested by the app.
  disconnecting,
}

/// A peripheral seen while scanning.
///
/// [id] is platform specific: on Android it is the MAC address
/// (`AA:BB:CC:DD:EE:FF`); on iOS it is a random UUID that CoreBluetooth
/// assigns per phone, so the same wearable has *different* IDs on two
/// iPhones and you can never learn its MAC on iOS. Keep that in mind when
/// persisting "last paired device" or writing IDs to NFC tags.
class DiscoveredPpgDevice extends Equatable {
  /// Creates a scan result.
  ///
  /// [id] is the OS-level identifier used to connect, [name] the advertised
  /// local name, and [rssi] the received signal strength in dBm (typically
  /// -30 very close .. -100 barely reachable); useful to sort by proximity.
  const DiscoveredPpgDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// OS-level identifier used to connect.
  final String id;

  /// Advertised local name (may be empty: many devices omit it to save
  /// advertising bytes, or iOS hides it until a scan response arrives).
  final String name;

  /// Signal strength in dBm.
  final int rssi;

  @override
  List<Object?> get props => [id, name, rssi];
}
