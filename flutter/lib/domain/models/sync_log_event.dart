enum SyncLogEventType {
  connectionTest,
  pushSucceeded,
  pushFailed,
  pullSucceeded,
  pullFailed,
  importSucceeded,
  importFailed;

  String get jsonValue {
    switch (this) {
      case SyncLogEventType.connectionTest:
        return 'connection_test';
      case SyncLogEventType.pushSucceeded:
        return 'push_succeeded';
      case SyncLogEventType.pushFailed:
        return 'push_failed';
      case SyncLogEventType.pullSucceeded:
        return 'pull_succeeded';
      case SyncLogEventType.pullFailed:
        return 'pull_failed';
      case SyncLogEventType.importSucceeded:
        return 'import_succeeded';
      case SyncLogEventType.importFailed:
        return 'import_failed';
    }
  }

  String get label {
    switch (this) {
      case SyncLogEventType.connectionTest:
        return 'Test de connexion';
      case SyncLogEventType.pushSucceeded:
        return 'Push envoyé';
      case SyncLogEventType.pushFailed:
        return 'Push en échec';
      case SyncLogEventType.pullSucceeded:
        return 'Pull récupéré';
      case SyncLogEventType.pullFailed:
        return 'Pull en échec';
      case SyncLogEventType.importSucceeded:
        return 'Snapshot importé';
      case SyncLogEventType.importFailed:
        return 'Import en échec';
    }
  }

  bool get isSuccess {
    switch (this) {
      case SyncLogEventType.connectionTest:
      case SyncLogEventType.pushSucceeded:
      case SyncLogEventType.pullSucceeded:
      case SyncLogEventType.importSucceeded:
        return true;
      case SyncLogEventType.pushFailed:
      case SyncLogEventType.pullFailed:
      case SyncLogEventType.importFailed:
        return false;
    }
  }

  static SyncLogEventType fromJson(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    switch (raw) {
      case 'connection_test':
      case 'connectiontest':
        return SyncLogEventType.connectionTest;
      case 'push_succeeded':
      case 'pushsucceeded':
        return SyncLogEventType.pushSucceeded;
      case 'push_failed':
      case 'pushfailed':
        return SyncLogEventType.pushFailed;
      case 'pull_succeeded':
      case 'pullsucceeded':
        return SyncLogEventType.pullSucceeded;
      case 'pull_failed':
      case 'pullfailed':
        return SyncLogEventType.pullFailed;
      case 'import_succeeded':
      case 'importsucceeded':
        return SyncLogEventType.importSucceeded;
      case 'import_failed':
      case 'importfailed':
        return SyncLogEventType.importFailed;
      default:
        return SyncLogEventType.connectionTest;
    }
  }
}

class SyncLogEvent {
  final String id;
  final SyncLogEventType type;
  final String tenantId;
  final String deviceId;
  final String title;
  final String message;
  final String? serverSyncId;
  final String? sourceDeviceId;
  final int? statusCode;
  final int? campaignCount;
  final int? snapshotCount;
  final DateTime createdAt;

  const SyncLogEvent({
    required this.id,
    required this.type,
    required this.tenantId,
    required this.deviceId,
    required this.title,
    required this.message,
    required this.createdAt,
    this.serverSyncId,
    this.sourceDeviceId,
    this.statusCode,
    this.campaignCount,
    this.snapshotCount,
  });

  factory SyncLogEvent.create({
    required SyncLogEventType type,
    required String tenantId,
    required String deviceId,
    required String title,
    required String message,
    String? serverSyncId,
    String? sourceDeviceId,
    int? statusCode,
    int? campaignCount,
    int? snapshotCount,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final safeTimestamp = timestamp.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    final safeTenant = _safeIdPart(tenantId.trim().isEmpty ? 'tenant' : tenantId.trim());
    return SyncLogEvent(
      id: 'sync-$safeTimestamp-${type.jsonValue}-$safeTenant',
      type: type,
      tenantId: tenantId.trim(),
      deviceId: deviceId.trim(),
      title: title.trim(),
      message: message.trim(),
      serverSyncId: _nullableTrim(serverSyncId),
      sourceDeviceId: _nullableTrim(sourceDeviceId),
      statusCode: statusCode,
      campaignCount: campaignCount,
      snapshotCount: snapshotCount,
      createdAt: timestamp,
    );
  }

  factory SyncLogEvent.fromJson(Map<String, dynamic> json) {
    return SyncLogEvent(
      id: json['id']?.toString() ?? '',
      type: SyncLogEventType.fromJson(json['type']),
      tenantId: json['tenantId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      serverSyncId: _nullableTrim(json['serverSyncId']?.toString()),
      sourceDeviceId: _nullableTrim(json['sourceDeviceId']?.toString()),
      statusCode: _intOrNull(json['statusCode']),
      campaignCount: _intOrNull(json['campaignCount']),
      snapshotCount: _intOrNull(json['snapshotCount']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.jsonValue,
      'typeLabel': type.label,
      'tenantId': tenantId,
      'deviceId': deviceId,
      'title': title,
      'message': message,
      if (serverSyncId != null) 'serverSyncId': serverSyncId,
      if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
      if (statusCode != null) 'statusCode': statusCode,
      if (campaignCount != null) 'campaignCount': campaignCount,
      if (snapshotCount != null) 'snapshotCount': snapshotCount,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  static int? _intOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String _safeIdPart(String value) {
    final safe = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return safe.replaceAll(RegExp(r'^-+|-+$'), '').trim();
  }
}
