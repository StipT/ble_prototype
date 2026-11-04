// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sampleRateHzMeta = const VerificationMeta(
    'sampleRateHz',
  );
  @override
  late final GeneratedColumn<int> sampleRateHz = GeneratedColumn<int>(
    'sample_rate_hz',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    startedAt,
    endedAt,
    sampleRateHz,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('sample_rate_hz')) {
      context.handle(
        _sampleRateHzMeta,
        sampleRateHz.isAcceptableOrUnknown(
          data['sample_rate_hz']!,
          _sampleRateHzMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sampleRateHzMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      sampleRateHz: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_rate_hz'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  /// Random 128-bit hex ID, also used in the Firestore path.
  final String id;

  /// OS identifier of the wearable that produced the data.
  final String deviceId;

  /// When the user pressed "Record".
  final DateTime startedAt;

  /// When the user pressed "Stop"; `null` while recording.
  final DateTime? endedAt;

  /// Samples per second of the stored signal.
  final int sampleRateHz;
  const SessionRow({
    required this.id,
    required this.deviceId,
    required this.startedAt,
    this.endedAt,
    required this.sampleRateHz,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['sample_rate_hz'] = Variable<int>(sampleRateHz);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      sampleRateHz: Value(sampleRateHz),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      sampleRateHz: serializer.fromJson<int>(json['sampleRateHz']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'sampleRateHz': serializer.toJson<int>(sampleRateHz),
    };
  }

  SessionRow copyWith({
    String? id,
    String? deviceId,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    int? sampleRateHz,
  }) => SessionRow(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    sampleRateHz: sampleRateHz ?? this.sampleRateHz,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      sampleRateHz: data.sampleRateHz.present
          ? data.sampleRateHz.value
          : this.sampleRateHz,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('sampleRateHz: $sampleRateHz')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, deviceId, startedAt, endedAt, sampleRateHz);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.sampleRateHz == this.sampleRateHz);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> sampleRateHz;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.sampleRateHz = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String deviceId,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    required int sampleRateHz,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deviceId = Value(deviceId),
       startedAt = Value(startedAt),
       sampleRateHz = Value(sampleRateHz);
  static Insertable<SessionRow> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? sampleRateHz,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? sampleRateHz,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (sampleRateHz.present) {
      map['sample_rate_hz'] = Variable<int>(sampleRateHz.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('sampleRateHz: $sampleRateHz, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PacketsTable extends Packets with TableInfo<$PacketsTable, PacketRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PacketsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _samplesMeta = const VerificationMeta(
    'samples',
  );
  @override
  late final GeneratedColumn<Uint8List> samples = GeneratedColumn<Uint8List>(
    'samples',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromHistoryMeta = const VerificationMeta(
    'fromHistory',
  );
  @override
  late final GeneratedColumn<bool> fromHistory = GeneratedColumn<bool>(
    'from_history',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("from_history" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    sequence,
    timestamp,
    samples,
    fromHistory,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'packets';
  @override
  VerificationContext validateIntegrity(
    Insertable<PacketRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('samples')) {
      context.handle(
        _samplesMeta,
        samples.isAcceptableOrUnknown(data['samples']!, _samplesMeta),
      );
    } else if (isInserting) {
      context.missing(_samplesMeta);
    }
    if (data.containsKey('from_history')) {
      context.handle(
        _fromHistoryMeta,
        fromHistory.isAcceptableOrUnknown(
          data['from_history']!,
          _fromHistoryMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, sequence};
  @override
  PacketRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PacketRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      samples: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}samples'],
      )!,
      fromHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}from_history'],
      )!,
    );
  }

  @override
  $PacketsTable createAlias(String alias) {
    return $PacketsTable(attachedDatabase, alias);
  }
}

class PacketRow extends DataClass implements Insertable<PacketRow> {
  /// Owning session.
  final String sessionId;

  /// Device sequence number.
  final int sequence;

  /// Time of the first sample.
  final DateTime timestamp;

  /// Samples packed as unsigned 24-bit little-endian (3 bytes each).
  final Uint8List samples;

  /// Whether the packet arrived through history sync.
  final bool fromHistory;
  const PacketRow({
    required this.sessionId,
    required this.sequence,
    required this.timestamp,
    required this.samples,
    required this.fromHistory,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['sequence'] = Variable<int>(sequence);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['samples'] = Variable<Uint8List>(samples);
    map['from_history'] = Variable<bool>(fromHistory);
    return map;
  }

  PacketsCompanion toCompanion(bool nullToAbsent) {
    return PacketsCompanion(
      sessionId: Value(sessionId),
      sequence: Value(sequence),
      timestamp: Value(timestamp),
      samples: Value(samples),
      fromHistory: Value(fromHistory),
    );
  }

  factory PacketRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PacketRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      samples: serializer.fromJson<Uint8List>(json['samples']),
      fromHistory: serializer.fromJson<bool>(json['fromHistory']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'sequence': serializer.toJson<int>(sequence),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'samples': serializer.toJson<Uint8List>(samples),
      'fromHistory': serializer.toJson<bool>(fromHistory),
    };
  }

  PacketRow copyWith({
    String? sessionId,
    int? sequence,
    DateTime? timestamp,
    Uint8List? samples,
    bool? fromHistory,
  }) => PacketRow(
    sessionId: sessionId ?? this.sessionId,
    sequence: sequence ?? this.sequence,
    timestamp: timestamp ?? this.timestamp,
    samples: samples ?? this.samples,
    fromHistory: fromHistory ?? this.fromHistory,
  );
  PacketRow copyWithCompanion(PacketsCompanion data) {
    return PacketRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      samples: data.samples.present ? data.samples.value : this.samples,
      fromHistory: data.fromHistory.present
          ? data.fromHistory.value
          : this.fromHistory,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PacketRow(')
          ..write('sessionId: $sessionId, ')
          ..write('sequence: $sequence, ')
          ..write('timestamp: $timestamp, ')
          ..write('samples: $samples, ')
          ..write('fromHistory: $fromHistory')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    sequence,
    timestamp,
    $driftBlobEquality.hash(samples),
    fromHistory,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PacketRow &&
          other.sessionId == this.sessionId &&
          other.sequence == this.sequence &&
          other.timestamp == this.timestamp &&
          $driftBlobEquality.equals(other.samples, this.samples) &&
          other.fromHistory == this.fromHistory);
}

class PacketsCompanion extends UpdateCompanion<PacketRow> {
  final Value<String> sessionId;
  final Value<int> sequence;
  final Value<DateTime> timestamp;
  final Value<Uint8List> samples;
  final Value<bool> fromHistory;
  final Value<int> rowid;
  const PacketsCompanion({
    this.sessionId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.samples = const Value.absent(),
    this.fromHistory = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PacketsCompanion.insert({
    required String sessionId,
    required int sequence,
    required DateTime timestamp,
    required Uint8List samples,
    this.fromHistory = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       sequence = Value(sequence),
       timestamp = Value(timestamp),
       samples = Value(samples);
  static Insertable<PacketRow> custom({
    Expression<String>? sessionId,
    Expression<int>? sequence,
    Expression<DateTime>? timestamp,
    Expression<Uint8List>? samples,
    Expression<bool>? fromHistory,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (sequence != null) 'sequence': sequence,
      if (timestamp != null) 'timestamp': timestamp,
      if (samples != null) 'samples': samples,
      if (fromHistory != null) 'from_history': fromHistory,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PacketsCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? sequence,
    Value<DateTime>? timestamp,
    Value<Uint8List>? samples,
    Value<bool>? fromHistory,
    Value<int>? rowid,
  }) {
    return PacketsCompanion(
      sessionId: sessionId ?? this.sessionId,
      sequence: sequence ?? this.sequence,
      timestamp: timestamp ?? this.timestamp,
      samples: samples ?? this.samples,
      fromHistory: fromHistory ?? this.fromHistory,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (samples.present) {
      map['samples'] = Variable<Uint8List>(samples.value);
    }
    if (fromHistory.present) {
      map['from_history'] = Variable<bool>(fromHistory.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PacketsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('sequence: $sequence, ')
          ..write('timestamp: $timestamp, ')
          ..write('samples: $samples, ')
          ..write('fromHistory: $fromHistory, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChunksTable extends Chunks with TableInfo<$ChunksTable, ChunkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chunkIndexMeta = const VerificationMeta(
    'chunkIndex',
  );
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
    'chunk_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packetCountMeta = const VerificationMeta(
    'packetCount',
  );
  @override
  late final GeneratedColumn<int> packetCount = GeneratedColumn<int>(
    'packet_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstSequenceMeta = const VerificationMeta(
    'firstSequence',
  );
  @override
  late final GeneratedColumn<int> firstSequence = GeneratedColumn<int>(
    'first_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSequenceMeta = const VerificationMeta(
    'lastSequence',
  );
  @override
  late final GeneratedColumn<int> lastSequence = GeneratedColumn<int>(
    'last_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChunkSyncState, String>
  syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<ChunkSyncState>($ChunksTable.$convertersyncState);
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _prunedAtMeta = const VerificationMeta(
    'prunedAt',
  );
  @override
  late final GeneratedColumn<DateTime> prunedAt = GeneratedColumn<DateTime>(
    'pruned_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    chunkIndex,
    packetCount,
    firstSequence,
    lastSequence,
    startedAt,
    syncState,
    attempts,
    nextAttemptAt,
    lastError,
    syncedAt,
    prunedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chunks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChunkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('chunk_index')) {
      context.handle(
        _chunkIndexMeta,
        chunkIndex.isAcceptableOrUnknown(data['chunk_index']!, _chunkIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkIndexMeta);
    }
    if (data.containsKey('packet_count')) {
      context.handle(
        _packetCountMeta,
        packetCount.isAcceptableOrUnknown(
          data['packet_count']!,
          _packetCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packetCountMeta);
    }
    if (data.containsKey('first_sequence')) {
      context.handle(
        _firstSequenceMeta,
        firstSequence.isAcceptableOrUnknown(
          data['first_sequence']!,
          _firstSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstSequenceMeta);
    }
    if (data.containsKey('last_sequence')) {
      context.handle(
        _lastSequenceMeta,
        lastSequence.isAcceptableOrUnknown(
          data['last_sequence']!,
          _lastSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSequenceMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('pruned_at')) {
      context.handle(
        _prunedAtMeta,
        prunedAt.isAcceptableOrUnknown(data['pruned_at']!, _prunedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, chunkIndex};
  @override
  ChunkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChunkRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      chunkIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_index'],
      )!,
      packetCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}packet_count'],
      )!,
      firstSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_sequence'],
      )!,
      lastSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sequence'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      syncState: $ChunksTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      prunedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pruned_at'],
      ),
    );
  }

  @override
  $ChunksTable createAlias(String alias) {
    return $ChunksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChunkSyncState, String, String>
  $convertersyncState = const EnumNameConverter<ChunkSyncState>(
    ChunkSyncState.values,
  );
}

class ChunkRow extends DataClass implements Insertable<ChunkRow> {
  /// Owning session.
  final String sessionId;

  /// `sequence ~/ packetsPerChunk`; with [sessionId] forms the Firestore
  /// document ID `sessionId_chunkIndex`.
  final int chunkIndex;

  /// Packets currently stored for this chunk.
  final int packetCount;

  /// Lowest stored sequence.
  final int firstSequence;

  /// Highest stored sequence.
  final int lastSequence;

  /// Timestamp of the earliest packet (used for pruning age).
  final DateTime startedAt;

  /// Upload state.
  final ChunkSyncState syncState;

  /// Failed upload attempts so far.
  final int attempts;

  /// Earliest time of the next retry (exponential backoff).
  final DateTime? nextAttemptAt;

  /// Message of the last upload failure.
  final String? lastError;

  /// When the upload succeeded.
  final DateTime? syncedAt;

  /// When the local packets were pruned (row kept as a tombstone so the
  /// chunk is never uploaded twice).
  final DateTime? prunedAt;
  const ChunkRow({
    required this.sessionId,
    required this.chunkIndex,
    required this.packetCount,
    required this.firstSequence,
    required this.lastSequence,
    required this.startedAt,
    required this.syncState,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
    this.syncedAt,
    this.prunedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['chunk_index'] = Variable<int>(chunkIndex);
    map['packet_count'] = Variable<int>(packetCount);
    map['first_sequence'] = Variable<int>(firstSequence);
    map['last_sequence'] = Variable<int>(lastSequence);
    map['started_at'] = Variable<DateTime>(startedAt);
    {
      map['sync_state'] = Variable<String>(
        $ChunksTable.$convertersyncState.toSql(syncState),
      );
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    if (!nullToAbsent || prunedAt != null) {
      map['pruned_at'] = Variable<DateTime>(prunedAt);
    }
    return map;
  }

  ChunksCompanion toCompanion(bool nullToAbsent) {
    return ChunksCompanion(
      sessionId: Value(sessionId),
      chunkIndex: Value(chunkIndex),
      packetCount: Value(packetCount),
      firstSequence: Value(firstSequence),
      lastSequence: Value(lastSequence),
      startedAt: Value(startedAt),
      syncState: Value(syncState),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      prunedAt: prunedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(prunedAt),
    );
  }

  factory ChunkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChunkRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      packetCount: serializer.fromJson<int>(json['packetCount']),
      firstSequence: serializer.fromJson<int>(json['firstSequence']),
      lastSequence: serializer.fromJson<int>(json['lastSequence']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      syncState: $ChunksTable.$convertersyncState.fromJson(
        serializer.fromJson<String>(json['syncState']),
      ),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      prunedAt: serializer.fromJson<DateTime?>(json['prunedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'packetCount': serializer.toJson<int>(packetCount),
      'firstSequence': serializer.toJson<int>(firstSequence),
      'lastSequence': serializer.toJson<int>(lastSequence),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'syncState': serializer.toJson<String>(
        $ChunksTable.$convertersyncState.toJson(syncState),
      ),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'prunedAt': serializer.toJson<DateTime?>(prunedAt),
    };
  }

  ChunkRow copyWith({
    String? sessionId,
    int? chunkIndex,
    int? packetCount,
    int? firstSequence,
    int? lastSequence,
    DateTime? startedAt,
    ChunkSyncState? syncState,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> syncedAt = const Value.absent(),
    Value<DateTime?> prunedAt = const Value.absent(),
  }) => ChunkRow(
    sessionId: sessionId ?? this.sessionId,
    chunkIndex: chunkIndex ?? this.chunkIndex,
    packetCount: packetCount ?? this.packetCount,
    firstSequence: firstSequence ?? this.firstSequence,
    lastSequence: lastSequence ?? this.lastSequence,
    startedAt: startedAt ?? this.startedAt,
    syncState: syncState ?? this.syncState,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    prunedAt: prunedAt.present ? prunedAt.value : this.prunedAt,
  );
  ChunkRow copyWithCompanion(ChunksCompanion data) {
    return ChunkRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      chunkIndex: data.chunkIndex.present
          ? data.chunkIndex.value
          : this.chunkIndex,
      packetCount: data.packetCount.present
          ? data.packetCount.value
          : this.packetCount,
      firstSequence: data.firstSequence.present
          ? data.firstSequence.value
          : this.firstSequence,
      lastSequence: data.lastSequence.present
          ? data.lastSequence.value
          : this.lastSequence,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      prunedAt: data.prunedAt.present ? data.prunedAt.value : this.prunedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChunkRow(')
          ..write('sessionId: $sessionId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('packetCount: $packetCount, ')
          ..write('firstSequence: $firstSequence, ')
          ..write('lastSequence: $lastSequence, ')
          ..write('startedAt: $startedAt, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('prunedAt: $prunedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    chunkIndex,
    packetCount,
    firstSequence,
    lastSequence,
    startedAt,
    syncState,
    attempts,
    nextAttemptAt,
    lastError,
    syncedAt,
    prunedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChunkRow &&
          other.sessionId == this.sessionId &&
          other.chunkIndex == this.chunkIndex &&
          other.packetCount == this.packetCount &&
          other.firstSequence == this.firstSequence &&
          other.lastSequence == this.lastSequence &&
          other.startedAt == this.startedAt &&
          other.syncState == this.syncState &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.syncedAt == this.syncedAt &&
          other.prunedAt == this.prunedAt);
}

class ChunksCompanion extends UpdateCompanion<ChunkRow> {
  final Value<String> sessionId;
  final Value<int> chunkIndex;
  final Value<int> packetCount;
  final Value<int> firstSequence;
  final Value<int> lastSequence;
  final Value<DateTime> startedAt;
  final Value<ChunkSyncState> syncState;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime?> syncedAt;
  final Value<DateTime?> prunedAt;
  final Value<int> rowid;
  const ChunksCompanion({
    this.sessionId = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.packetCount = const Value.absent(),
    this.firstSequence = const Value.absent(),
    this.lastSequence = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.prunedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChunksCompanion.insert({
    required String sessionId,
    required int chunkIndex,
    required int packetCount,
    required int firstSequence,
    required int lastSequence,
    required DateTime startedAt,
    required ChunkSyncState syncState,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.prunedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       chunkIndex = Value(chunkIndex),
       packetCount = Value(packetCount),
       firstSequence = Value(firstSequence),
       lastSequence = Value(lastSequence),
       startedAt = Value(startedAt),
       syncState = Value(syncState);
  static Insertable<ChunkRow> custom({
    Expression<String>? sessionId,
    Expression<int>? chunkIndex,
    Expression<int>? packetCount,
    Expression<int>? firstSequence,
    Expression<int>? lastSequence,
    Expression<DateTime>? startedAt,
    Expression<String>? syncState,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<DateTime>? syncedAt,
    Expression<DateTime>? prunedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (chunkIndex != null) 'chunk_index': chunkIndex,
      if (packetCount != null) 'packet_count': packetCount,
      if (firstSequence != null) 'first_sequence': firstSequence,
      if (lastSequence != null) 'last_sequence': lastSequence,
      if (startedAt != null) 'started_at': startedAt,
      if (syncState != null) 'sync_state': syncState,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (prunedAt != null) 'pruned_at': prunedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChunksCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? chunkIndex,
    Value<int>? packetCount,
    Value<int>? firstSequence,
    Value<int>? lastSequence,
    Value<DateTime>? startedAt,
    Value<ChunkSyncState>? syncState,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<DateTime?>? syncedAt,
    Value<DateTime?>? prunedAt,
    Value<int>? rowid,
  }) {
    return ChunksCompanion(
      sessionId: sessionId ?? this.sessionId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      packetCount: packetCount ?? this.packetCount,
      firstSequence: firstSequence ?? this.firstSequence,
      lastSequence: lastSequence ?? this.lastSequence,
      startedAt: startedAt ?? this.startedAt,
      syncState: syncState ?? this.syncState,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      syncedAt: syncedAt ?? this.syncedAt,
      prunedAt: prunedAt ?? this.prunedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (chunkIndex.present) {
      map['chunk_index'] = Variable<int>(chunkIndex.value);
    }
    if (packetCount.present) {
      map['packet_count'] = Variable<int>(packetCount.value);
    }
    if (firstSequence.present) {
      map['first_sequence'] = Variable<int>(firstSequence.value);
    }
    if (lastSequence.present) {
      map['last_sequence'] = Variable<int>(lastSequence.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(
        $ChunksTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (prunedAt.present) {
      map['pruned_at'] = Variable<DateTime>(prunedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChunksCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('packetCount: $packetCount, ')
          ..write('firstSequence: $firstSequence, ')
          ..write('lastSequence: $lastSequence, ')
          ..write('startedAt: $startedAt, ')
          ..write('syncState: $syncState, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('prunedAt: $prunedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $PacketsTable packets = $PacketsTable(this);
  late final $ChunksTable chunks = $ChunksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sessions,
    packets,
    chunks,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('packets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('chunks', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String deviceId,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      required int sampleRateHz,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> sampleRateHz,
      Value<int> rowid,
    });

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, SessionRow> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PacketsTable, List<PacketRow>> _packetsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.packets,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.packets.sessionId),
  );

  $$PacketsTableProcessedTableManager get packetsRefs {
    final manager = $$PacketsTableTableManager(
      $_db,
      $_db.packets,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_packetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChunksTable, List<ChunkRow>> _chunksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chunks,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.chunks.sessionId),
  );

  $$ChunksTableProcessedTableManager get chunksRefs {
    final manager = $$ChunksTableTableManager(
      $_db,
      $_db.chunks,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chunksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> packetsRefs(
    Expression<bool> Function($$PacketsTableFilterComposer f) f,
  ) {
    final $$PacketsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.packets,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PacketsTableFilterComposer(
            $db: $db,
            $table: $db.packets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> chunksRefs(
    Expression<bool> Function($$ChunksTableFilterComposer f) f,
  ) {
    final $$ChunksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chunks,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChunksTableFilterComposer(
            $db: $db,
            $table: $db.chunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => column,
  );

  Expression<T> packetsRefs<T extends Object>(
    Expression<T> Function($$PacketsTableAnnotationComposer a) f,
  ) {
    final $$PacketsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.packets,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PacketsTableAnnotationComposer(
            $db: $db,
            $table: $db.packets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> chunksRefs<T extends Object>(
    Expression<T> Function($$ChunksTableAnnotationComposer a) f,
  ) {
    final $$ChunksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chunks,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChunksTableAnnotationComposer(
            $db: $db,
            $table: $db.chunks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          SessionRow,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (SessionRow, $$SessionsTableReferences),
          SessionRow,
          PrefetchHooks Function({bool packetsRefs, bool chunksRefs})
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> sampleRateHz = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                deviceId: deviceId,
                startedAt: startedAt,
                endedAt: endedAt,
                sampleRateHz: sampleRateHz,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deviceId,
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                required int sampleRateHz,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                deviceId: deviceId,
                startedAt: startedAt,
                endedAt: endedAt,
                sampleRateHz: sampleRateHz,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({packetsRefs = false, chunksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (packetsRefs) db.packets,
                if (chunksRefs) db.chunks,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (packetsRefs)
                    await $_getPrefetchedData<
                      SessionRow,
                      $SessionsTable,
                      PacketRow
                    >(
                      currentTable: table,
                      referencedTable: $$SessionsTableReferences
                          ._packetsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SessionsTableReferences(db, table, p0).packetsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sessionId == item.id),
                      typedResults: items,
                    ),
                  if (chunksRefs)
                    await $_getPrefetchedData<
                      SessionRow,
                      $SessionsTable,
                      ChunkRow
                    >(
                      currentTable: table,
                      referencedTable: $$SessionsTableReferences
                          ._chunksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SessionsTableReferences(db, table, p0).chunksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sessionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      SessionRow,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (SessionRow, $$SessionsTableReferences),
      SessionRow,
      PrefetchHooks Function({bool packetsRefs, bool chunksRefs})
    >;
typedef $$PacketsTableCreateCompanionBuilder =
    PacketsCompanion Function({
      required String sessionId,
      required int sequence,
      required DateTime timestamp,
      required Uint8List samples,
      Value<bool> fromHistory,
      Value<int> rowid,
    });
typedef $$PacketsTableUpdateCompanionBuilder =
    PacketsCompanion Function({
      Value<String> sessionId,
      Value<int> sequence,
      Value<DateTime> timestamp,
      Value<Uint8List> samples,
      Value<bool> fromHistory,
      Value<int> rowid,
    });

final class $$PacketsTableReferences
    extends BaseReferences<_$AppDatabase, $PacketsTable, PacketRow> {
  $$PacketsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) => db.sessions
      .createAlias($_aliasNameGenerator(db.packets.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PacketsTableFilterComposer
    extends Composer<_$AppDatabase, $PacketsTable> {
  $$PacketsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get samples => $composableBuilder(
    column: $table.samples,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fromHistory => $composableBuilder(
    column: $table.fromHistory,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PacketsTableOrderingComposer
    extends Composer<_$AppDatabase, $PacketsTable> {
  $$PacketsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get samples => $composableBuilder(
    column: $table.samples,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fromHistory => $composableBuilder(
    column: $table.fromHistory,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PacketsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PacketsTable> {
  $$PacketsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<Uint8List> get samples =>
      $composableBuilder(column: $table.samples, builder: (column) => column);

  GeneratedColumn<bool> get fromHistory => $composableBuilder(
    column: $table.fromHistory,
    builder: (column) => column,
  );

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PacketsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PacketsTable,
          PacketRow,
          $$PacketsTableFilterComposer,
          $$PacketsTableOrderingComposer,
          $$PacketsTableAnnotationComposer,
          $$PacketsTableCreateCompanionBuilder,
          $$PacketsTableUpdateCompanionBuilder,
          (PacketRow, $$PacketsTableReferences),
          PacketRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$PacketsTableTableManager(_$AppDatabase db, $PacketsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PacketsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PacketsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PacketsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<Uint8List> samples = const Value.absent(),
                Value<bool> fromHistory = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PacketsCompanion(
                sessionId: sessionId,
                sequence: sequence,
                timestamp: timestamp,
                samples: samples,
                fromHistory: fromHistory,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int sequence,
                required DateTime timestamp,
                required Uint8List samples,
                Value<bool> fromHistory = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PacketsCompanion.insert(
                sessionId: sessionId,
                sequence: sequence,
                timestamp: timestamp,
                samples: samples,
                fromHistory: fromHistory,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PacketsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$PacketsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$PacketsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PacketsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PacketsTable,
      PacketRow,
      $$PacketsTableFilterComposer,
      $$PacketsTableOrderingComposer,
      $$PacketsTableAnnotationComposer,
      $$PacketsTableCreateCompanionBuilder,
      $$PacketsTableUpdateCompanionBuilder,
      (PacketRow, $$PacketsTableReferences),
      PacketRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ChunksTableCreateCompanionBuilder =
    ChunksCompanion Function({
      required String sessionId,
      required int chunkIndex,
      required int packetCount,
      required int firstSequence,
      required int lastSequence,
      required DateTime startedAt,
      required ChunkSyncState syncState,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime?> syncedAt,
      Value<DateTime?> prunedAt,
      Value<int> rowid,
    });
typedef $$ChunksTableUpdateCompanionBuilder =
    ChunksCompanion Function({
      Value<String> sessionId,
      Value<int> chunkIndex,
      Value<int> packetCount,
      Value<int> firstSequence,
      Value<int> lastSequence,
      Value<DateTime> startedAt,
      Value<ChunkSyncState> syncState,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime?> syncedAt,
      Value<DateTime?> prunedAt,
      Value<int> rowid,
    });

final class $$ChunksTableReferences
    extends BaseReferences<_$AppDatabase, $ChunksTable, ChunkRow> {
  $$ChunksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) => db.sessions
      .createAlias($_aliasNameGenerator(db.chunks.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChunksTableFilterComposer
    extends Composer<_$AppDatabase, $ChunksTable> {
  $$ChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get packetCount => $composableBuilder(
    column: $table.packetCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSequence => $composableBuilder(
    column: $table.firstSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSequence => $composableBuilder(
    column: $table.lastSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChunkSyncState, ChunkSyncState, String>
  get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get prunedAt => $composableBuilder(
    column: $table.prunedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChunksTableOrderingComposer
    extends Composer<_$AppDatabase, $ChunksTable> {
  $$ChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get packetCount => $composableBuilder(
    column: $table.packetCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSequence => $composableBuilder(
    column: $table.firstSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSequence => $composableBuilder(
    column: $table.lastSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get prunedAt => $composableBuilder(
    column: $table.prunedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChunksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChunksTable> {
  $$ChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get packetCount => $composableBuilder(
    column: $table.packetCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstSequence => $composableBuilder(
    column: $table.firstSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSequence => $composableBuilder(
    column: $table.lastSequence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChunkSyncState, String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get prunedAt =>
      $composableBuilder(column: $table.prunedAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChunksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChunksTable,
          ChunkRow,
          $$ChunksTableFilterComposer,
          $$ChunksTableOrderingComposer,
          $$ChunksTableAnnotationComposer,
          $$ChunksTableCreateCompanionBuilder,
          $$ChunksTableUpdateCompanionBuilder,
          (ChunkRow, $$ChunksTableReferences),
          ChunkRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$ChunksTableTableManager(_$AppDatabase db, $ChunksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> chunkIndex = const Value.absent(),
                Value<int> packetCount = const Value.absent(),
                Value<int> firstSequence = const Value.absent(),
                Value<int> lastSequence = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<ChunkSyncState> syncState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<DateTime?> prunedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChunksCompanion(
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                packetCount: packetCount,
                firstSequence: firstSequence,
                lastSequence: lastSequence,
                startedAt: startedAt,
                syncState: syncState,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                syncedAt: syncedAt,
                prunedAt: prunedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int chunkIndex,
                required int packetCount,
                required int firstSequence,
                required int lastSequence,
                required DateTime startedAt,
                required ChunkSyncState syncState,
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<DateTime?> prunedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChunksCompanion.insert(
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                packetCount: packetCount,
                firstSequence: firstSequence,
                lastSequence: lastSequence,
                startedAt: startedAt,
                syncState: syncState,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                syncedAt: syncedAt,
                prunedAt: prunedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$ChunksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$ChunksTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$ChunksTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChunksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChunksTable,
      ChunkRow,
      $$ChunksTableFilterComposer,
      $$ChunksTableOrderingComposer,
      $$ChunksTableAnnotationComposer,
      $$ChunksTableCreateCompanionBuilder,
      $$ChunksTableUpdateCompanionBuilder,
      (ChunkRow, $$ChunksTableReferences),
      ChunkRow,
      PrefetchHooks Function({bool sessionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$PacketsTableTableManager get packets =>
      $$PacketsTableTableManager(_db, _db.packets);
  $$ChunksTableTableManager get chunks =>
      $$ChunksTableTableManager(_db, _db.chunks);
}
