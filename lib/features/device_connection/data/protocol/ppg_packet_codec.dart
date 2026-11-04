import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/device_status.dart';
import '../../domain/entities/ppg_packet.dart';

/// Everything that is decoded from the PPG notify characteristic.
///
/// The same characteristic carries live packets, replayed history packets and
/// an end-of-history marker, distinguished by the first byte (the "frame
/// type"). Multiplexing on one characteristic keeps the GATT table small and
/// guarantees ordering: BLE preserves order *within* one characteristic, but
/// notifications from two different characteristics may interleave.
sealed class PpgFrame extends Equatable {
  const PpgFrame();
}

/// A live or history packet.
final class PpgDataFrame extends PpgFrame {
  /// Wraps a decoded [packet].
  const PpgDataFrame(this.packet);

  /// The decoded packet.
  final PpgPacket packet;

  @override
  List<Object?> get props => [packet];
}

/// Marks the end of the answer to one history request.
///
/// Without a terminator the app could not tell "history finished" from
/// "device is slow" and would have to rely on timeouts.
final class HistoryEndFrame extends PpgFrame {
  /// [fromSequence]..[toSequence] echo the request; [sentCount] is how many
  /// packets the device actually had (fewer if some were already overwritten).
  const HistoryEndFrame({
    required this.fromSequence,
    required this.toSequence,
    required this.sentCount,
  });

  /// First requested sequence (inclusive).
  final int fromSequence;

  /// Last requested sequence (inclusive).
  final int toSequence;

  /// Packets actually replayed.
  final int sentCount;

  @override
  List<Object?> get props => [fromSequence, toSequence, sentCount];
}

/// Commands written to the control characteristic.
sealed class ControlCommand extends Equatable {
  const ControlCommand();

  @override
  List<Object?> get props => [];
}

/// Ask the device to start pushing live notifications.
final class StartStreamingCommand extends ControlCommand {
  /// Creates the command.
  const StartStreamingCommand();
}

/// Ask the device to stop pushing live notifications (it keeps measuring and
/// storing into its backlog).
final class StopStreamingCommand extends ControlCommand {
  /// Creates the command.
  const StopStreamingCommand();
}

/// Set the device clock so packet timestamps match the phone's wall clock.
///
/// Wearables usually have no RTC battery backup and boot at epoch 0; syncing
/// the clock right after every connect avoids timestamps from 1970.
final class SyncClockCommand extends ControlCommand {
  /// [now] becomes the device's current time.
  const SyncClockCommand(this.now);

  /// Time to set.
  final DateTime now;

  @override
  List<Object?> get props => [now];
}

/// Ask the device to replay stored packets [fromSequence]..[toSequence]
/// (inclusive) as history frames, followed by a [HistoryEndFrame].
final class RequestHistoryCommand extends ControlCommand {
  /// Creates a request for the inclusive range [fromSequence]..[toSequence].
  const RequestHistoryCommand(this.fromSequence, this.toSequence);

  /// First sequence to replay.
  final int fromSequence;

  /// Last sequence to replay.
  final int toSequence;

  @override
  List<Object?> get props => [fromSequence, toSequence];
}

/// The single place that knows the (placeholder) GATT protocol: UUIDs and the
/// byte layout of every characteristic. Swap this class to support real
/// hardware; nothing else in the app touches raw bytes.
///
/// ## GATT in one paragraph
/// A BLE peripheral exposes *services* (grouping, identified by a UUID), each
/// with *characteristics* (a value slot + properties such as read, write,
/// write-without-response, notify, indicate). The phone (GATT client)
/// subscribes to a characteristic by writing `0x0001` (notify) or `0x0002`
/// (indicate) into its Client Characteristic Configuration Descriptor
/// (CCCD, UUID 0x2902); plugins do this for you when you "subscribe".
///
/// * **Notify** = fire-and-forget, no link-layer ack from the app. Fast, used
///   for the PPG stream where an occasional lost packet is acceptable because
///   we can backfill via sequence numbers.
/// * **Indicate** = acknowledged by the client before the next one is sent;
///   reliable but halves throughput. Not used here.
///
/// ## Byte layout (all integers little-endian, the BLE convention)
/// PPG frame (notify, characteristic [ppgCharacteristicUuid]):
/// ```
/// live/history: [type u8 = 0x01|0x02][seq u32][timestampMs u64][n u8][n × sample u24]
/// history end:  [type u8 = 0x03][fromSeq u32][toSeq u32][sentCount u32]
/// ```
/// Control (write, [controlCharacteristicUuid]):
/// ```
/// [opcode u8] 0x01 start | 0x02 stop | 0x03 setClock [ms u64] | 0x04 history [from u32][to u32]
/// ```
/// Status (read + notify, [statusCharacteristicUuid]):
/// ```
/// [battery u8][flags u8: b0 streaming, b1 charging, b2 hasData][oldestSeq u32][latestSeq u32]
/// ```
///
/// ## MTU gotcha
/// The ATT MTU defaults to 23 bytes, leaving **20 bytes** of payload per
/// notification. A data frame with 5 samples is 14 + 15 = 29 bytes, so the
/// app must negotiate a larger MTU after connecting (Android: explicit
/// `requestMtu`, max 517; iOS: negotiated automatically, typically 185).
/// Payloads larger than MTU-3 are silently truncated by some stacks, which is
/// exactly what the length checks below catch.
class PpgPacketCodec {
  /// Creates the codec. Stateless; safe to share.
  const PpgPacketCodec();

  /// Primary service advertised by the wearable. Scanning with a service
  /// filter is mandatory on iOS for background scans and strongly
  /// recommended on Android (unfiltered scans get throttled to 5 per 30 s).
  static const serviceUuid = '7b5a0001-3c1e-4f6a-9d2b-5e8c0a1f2d3e';

  /// PPG samples (notify). Carries [PpgFrame]s.
  static const ppgCharacteristicUuid = '7b5a0002-3c1e-4f6a-9d2b-5e8c0a1f2d3e';

  /// Commands (write with response). Write-*with*-response is used because
  /// commands are rare and we want the GATT layer to confirm delivery.
  static const controlCharacteristicUuid =
      '7b5a0003-3c1e-4f6a-9d2b-5e8c0a1f2d3e';

  /// Battery + stored-range status (read + notify).
  static const statusCharacteristicUuid =
      '7b5a0004-3c1e-4f6a-9d2b-5e8c0a1f2d3e';

  /// Device sampling rate. Fixed by the (placeholder) firmware.
  static const sampleRateHz = 50;

  /// Samples the firmware puts in one packet (10 packets/second at 50 Hz).
  static const samplesPerPacket = 5;

  /// MTU the app asks for after connecting.
  static const preferredMtu = 247;

  /// ATT header overhead: an MTU of N leaves N - 3 bytes for the value.
  static const attHeaderBytes = 3;

  /// Largest notification payload we accept (preferred MTU minus ATT header).
  static const maxFrameBytes = preferredMtu - attHeaderBytes;

  /// Header size of a data frame (type + seq + timestamp + count).
  static const dataHeaderBytes = 1 + 4 + 8 + 1;

  /// Bytes per sample (24-bit).
  static const bytesPerSample = 3;

  /// Most samples that fit in [maxFrameBytes].
  static const maxSamplesPerPacket =
      (maxFrameBytes - dataHeaderBytes) ~/ bytesPerSample;

  /// Largest value a 24-bit unsigned sample can hold.
  static const maxSampleValue = 0xFFFFFF;

  /// Frame type byte of a live data frame.
  static const typeLive = 0x01;

  /// Frame type byte of a history data frame.
  static const typeHistory = 0x02;

  /// Frame type byte of the end-of-history marker.
  static const typeHistoryEnd = 0x03;

  static const _historyEndBytes = 1 + 4 + 4 + 4;
  static const _statusBytes = 1 + 1 + 4 + 4;
  static const _maxU32 = 0xFFFFFFFF;

  static const _opStart = 0x01;
  static const _opStop = 0x02;
  static const _opSetClock = 0x03;
  static const _opHistory = 0x04;

  /// Encodes [packet] as a data frame (used by the fake device and tests).
  ///
  /// Throws [ArgumentError] for values that cannot be represented; encoding
  /// is only done by code we control, so that is a programming error.
  Uint8List encodePacket(PpgPacket packet) {
    final n = packet.samples.length;
    if (n == 0 || n > maxSamplesPerPacket) {
      throw ArgumentError.value(n, 'samples.length');
    }
    _checkU32(packet.sequence, 'sequence');
    final bytes = ByteData(dataHeaderBytes + n * bytesPerSample)
      ..setUint8(0, packet.kind == PpgPacketKind.live ? typeLive : typeHistory)
      ..setUint32(1, packet.sequence, Endian.little)
      ..setUint64(5, packet.timestamp.millisecondsSinceEpoch, Endian.little)
      ..setUint8(13, n);
    var offset = dataHeaderBytes;
    for (final s in packet.samples) {
      if (s < 0 || s > maxSampleValue) {
        throw ArgumentError.value(s, 'sample', 'not a 24-bit unsigned value');
      }
      bytes
        ..setUint8(offset, s & 0xFF)
        ..setUint8(offset + 1, (s >> 8) & 0xFF)
        ..setUint8(offset + 2, (s >> 16) & 0xFF);
      offset += bytesPerSample;
    }
    return bytes.buffer.asUint8List();
  }

  /// Encodes the end-of-history marker (used by the fake device and tests).
  Uint8List encodeHistoryEnd(HistoryEndFrame frame) {
    _checkU32(frame.fromSequence, 'fromSequence');
    _checkU32(frame.toSequence, 'toSequence');
    return (ByteData(_historyEndBytes)
          ..setUint8(0, typeHistoryEnd)
          ..setUint32(1, frame.fromSequence, Endian.little)
          ..setUint32(5, frame.toSequence, Endian.little)
          ..setUint32(9, frame.sentCount, Endian.little))
        .buffer
        .asUint8List();
  }

  /// Decodes one notification from the PPG characteristic.
  ///
  /// Returns [ProtocolError] for empty, truncated, oversize, wrong-length or
  /// unknown-type input instead of throwing: a corrupted notification must
  /// never crash the stream, it is counted and skipped.
  Result<PpgFrame, ProtocolError> decodeFrame(List<int> raw) {
    if (raw.isEmpty) return const Err(ProtocolError('Empty frame'));
    if (raw.length > maxFrameBytes) {
      return Err(
        ProtocolError('Oversize frame: ${raw.length} > $maxFrameBytes bytes'),
      );
    }
    final bytes = _byteData(raw);
    final type = bytes.getUint8(0);
    switch (type) {
      case typeLive || typeHistory:
        if (raw.length < dataHeaderBytes) {
          return Err(ProtocolError('Truncated header: ${raw.length} bytes'));
        }
        final n = bytes.getUint8(13);
        if (n == 0 || n > maxSamplesPerPacket) {
          return Err(ProtocolError('Invalid sample count: $n'));
        }
        final expected = dataHeaderBytes + n * bytesPerSample;
        if (raw.length != expected) {
          return Err(
            ProtocolError(
              'Bad length: ${raw.length} bytes, header says $expected',
            ),
          );
        }
        final samples = List<int>.generate(n, (i) {
          final o = dataHeaderBytes + i * bytesPerSample;
          return bytes.getUint8(o) |
              (bytes.getUint8(o + 1) << 8) |
              (bytes.getUint8(o + 2) << 16);
        }, growable: false);
        return Ok(
          PpgDataFrame(
            PpgPacket(
              sequence: bytes.getUint32(1, Endian.little),
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                bytes.getUint64(5, Endian.little),
              ),
              samples: samples,
              kind: type == typeLive
                  ? PpgPacketKind.live
                  : PpgPacketKind.history,
            ),
          ),
        );
      case typeHistoryEnd:
        if (raw.length != _historyEndBytes) {
          return Err(
            ProtocolError(
              'Bad history-end length: ${raw.length}, expected '
              '$_historyEndBytes',
            ),
          );
        }
        return Ok(
          HistoryEndFrame(
            fromSequence: bytes.getUint32(1, Endian.little),
            toSequence: bytes.getUint32(5, Endian.little),
            sentCount: bytes.getUint32(9, Endian.little),
          ),
        );
      default:
        return Err(
          ProtocolError('Unknown frame type 0x${type.toRadixString(16)}'),
        );
    }
  }

  /// Encodes a control [command] for a GATT write.
  Uint8List encodeCommand(ControlCommand command) => switch (command) {
    StartStreamingCommand() => Uint8List.fromList([_opStart]),
    StopStreamingCommand() => Uint8List.fromList([_opStop]),
    SyncClockCommand(:final now) =>
      (ByteData(9)
            ..setUint8(0, _opSetClock)
            ..setUint64(1, now.millisecondsSinceEpoch, Endian.little))
          .buffer
          .asUint8List(),
    RequestHistoryCommand(:final fromSequence, :final toSequence) => () {
      _checkU32(fromSequence, 'fromSequence');
      _checkU32(toSequence, 'toSequence');
      return (ByteData(9)
            ..setUint8(0, _opHistory)
            ..setUint32(1, fromSequence, Endian.little)
            ..setUint32(5, toSequence, Endian.little))
          .buffer
          .asUint8List();
    }(),
  };

  /// Decodes a control write (the fake device's side of the protocol).
  Result<ControlCommand, ProtocolError> decodeCommand(List<int> raw) {
    if (raw.isEmpty) return const Err(ProtocolError('Empty command'));
    final bytes = _byteData(raw);
    final op = bytes.getUint8(0);
    switch (op) {
      case _opStart when raw.length == 1:
        return const Ok(StartStreamingCommand());
      case _opStop when raw.length == 1:
        return const Ok(StopStreamingCommand());
      case _opSetClock when raw.length == 9:
        return Ok(
          SyncClockCommand(
            DateTime.fromMillisecondsSinceEpoch(
              bytes.getUint64(1, Endian.little),
            ),
          ),
        );
      case _opHistory when raw.length == 9:
        final from = bytes.getUint32(1, Endian.little);
        final to = bytes.getUint32(5, Endian.little);
        if (from > to) {
          return Err(ProtocolError('History range inverted: $from > $to'));
        }
        return Ok(RequestHistoryCommand(from, to));
      default:
        return Err(
          ProtocolError(
            'Bad command 0x${op.toRadixString(16)} (${raw.length} bytes)',
          ),
        );
    }
  }

  /// Encodes a status value (the fake device's side of the protocol).
  Uint8List encodeStatus(DeviceStatus status) =>
      (ByteData(_statusBytes)
            ..setUint8(0, status.batteryPercent.clamp(0, 100))
            ..setUint8(
              1,
              (status.isStreaming ? 0x01 : 0) |
                  (status.isCharging ? 0x02 : 0) |
                  (status.hasData ? 0x04 : 0),
            )
            ..setUint32(2, status.oldestSequence, Endian.little)
            ..setUint32(6, status.latestSequence, Endian.little))
          .buffer
          .asUint8List();

  /// Decodes a read or notification of the status characteristic.
  Result<DeviceStatus, ProtocolError> decodeStatus(List<int> raw) {
    if (raw.length != _statusBytes) {
      return Err(
        ProtocolError(
          'Bad status length: ${raw.length}, expected $_statusBytes',
        ),
      );
    }
    final bytes = _byteData(raw);
    final battery = bytes.getUint8(0);
    if (battery > 100) {
      return Err(ProtocolError('Battery out of range: $battery'));
    }
    final flags = bytes.getUint8(1);
    return Ok(
      DeviceStatus(
        batteryPercent: battery,
        isStreaming: flags & 0x01 != 0,
        isCharging: flags & 0x02 != 0,
        hasData: flags & 0x04 != 0,
        oldestSequence: bytes.getUint32(2, Endian.little),
        latestSequence: bytes.getUint32(6, Endian.little),
      ),
    );
  }

  static ByteData _byteData(List<int> raw) {
    final list = raw is Uint8List ? raw : Uint8List.fromList(raw);
    return ByteData.sublistView(list);
  }

  static void _checkU32(int value, String name) {
    if (value < 0 || value > _maxU32) {
      throw ArgumentError.value(value, name, 'not an unsigned 32-bit value');
    }
  }
}
