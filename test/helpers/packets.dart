import 'package:ble_prototype/features/device_connection/domain/entities/ppg_packet.dart';

/// Test packet with sequence [seq].
PpgPacket packet(int seq, {PpgPacketKind kind = PpgPacketKind.live}) =>
    PpgPacket(
      sequence: seq,
      timestamp: DateTime.utc(
        2026,
        1,
        1,
      ).add(Duration(milliseconds: 100 * seq)),
      samples: [seq, seq + 1, seq + 2, 0xFFFFFF, 0],
      kind: kind,
    );

/// Packets for sequences [from]..[to] inclusive.
List<PpgPacket> packets(
  int from,
  int to, {
  PpgPacketKind kind = PpgPacketKind.live,
}) => [for (var s = from; s <= to; s++) packet(s, kind: kind)];
