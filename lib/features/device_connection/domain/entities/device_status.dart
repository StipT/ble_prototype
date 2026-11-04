import 'package:equatable/equatable.dart';

/// Snapshot of the wearable's state, read from the status/battery
/// characteristic.
///
/// The app reads it once after connecting (a GATT *read*) and then receives
/// updates as *notifications* whenever the battery level or stored range
/// changes. [oldestSequence]..[latestSequence] tells the app which packets
/// the device can still replay; anything older has been overwritten in the
/// device's ring buffer and is lost for good.
class DeviceStatus extends Equatable {
  /// Creates a status snapshot.
  ///
  /// [batteryPercent] is 0..100. [isStreaming] mirrors the last start/stop
  /// command. [isCharging] is true on the charger. [hasData] is false on a
  /// freshly booted device; in that case [oldestSequence] and
  /// [latestSequence] are meaningless.
  const DeviceStatus({
    required this.batteryPercent,
    required this.isStreaming,
    required this.isCharging,
    required this.hasData,
    required this.oldestSequence,
    required this.latestSequence,
  });

  /// Battery level, 0..100 %.
  final int batteryPercent;

  /// Whether the device is currently pushing live notifications.
  final bool isStreaming;

  /// Whether the device is on its charger.
  final bool isCharging;

  /// Whether the device has stored any packet yet.
  final bool hasData;

  /// Oldest sequence number still held in the device backlog.
  final int oldestSequence;

  /// Newest sequence number the device has produced.
  final int latestSequence;

  @override
  List<Object?> get props => [
    batteryPercent,
    isStreaming,
    isCharging,
    hasData,
    oldestSequence,
    latestSequence,
  ];
}
