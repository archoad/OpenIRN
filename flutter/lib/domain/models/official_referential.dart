class OfficialReferentialSummary {
  final String historyId;
  final String referentialId;
  final String version;
  final bool active;
  final String sourceUrl;
  final String projectPath;
  final String defaultBranch;
  final String filePath;
  final String sourceBlobId;
  final String sourceCommitSha;
  final String sourceSha256;
  final String canonicalSha256;
  final DateTime? downloadedAt;
  final DateTime? importedAt;
  final int pillarCount;
  final int criterionCount;
  final String validationStatus;
  final String webUrl;
  final String triggeredByUserId;
  final Map<String, dynamic> scoringMethod;

  const OfficialReferentialSummary({
    required this.historyId,
    required this.referentialId,
    required this.version,
    required this.active,
    required this.sourceUrl,
    required this.projectPath,
    required this.defaultBranch,
    required this.filePath,
    required this.sourceBlobId,
    required this.sourceCommitSha,
    required this.sourceSha256,
    required this.canonicalSha256,
    required this.downloadedAt,
    required this.importedAt,
    required this.pillarCount,
    required this.criterionCount,
    required this.validationStatus,
    required this.webUrl,
    required this.triggeredByUserId,
    this.scoringMethod = const <String, dynamic>{},
  });

  factory OfficialReferentialSummary.fromJson(Map<String, dynamic> json) {
    final sourceBlobId =
        json['sourceBlobId']?.toString() ?? json['blobId']?.toString() ?? '';
    return OfficialReferentialSummary(
      historyId: json['historyId']?.toString() ?? '',
      referentialId:
          json['referentialId']?.toString() ?? json['id']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      active: json['active'] is bool ? json['active'] as bool : true,
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      projectPath: json['projectPath']?.toString() ?? '',
      defaultBranch: json['defaultBranch']?.toString() ?? '',
      filePath: json['filePath']?.toString() ?? '',
      sourceBlobId: sourceBlobId,
      sourceCommitSha:
          json['sourceCommitSha']?.toString() ??
          json['commitSha']?.toString() ??
          '',
      sourceSha256: json['sourceSha256']?.toString() ?? '',
      canonicalSha256: json['canonicalSha256']?.toString() ?? '',
      downloadedAt: DateTime.tryParse(
        json['downloadedAt']?.toString() ?? '',
      )?.toLocal(),
      importedAt: DateTime.tryParse(
        json['importedAt']?.toString() ?? '',
      )?.toLocal(),
      pillarCount: _intFromJson(json['pillarCount']),
      criterionCount: _intFromJson(json['criterionCount']),
      validationStatus: json['validationStatus']?.toString() ?? '',
      webUrl: json['webUrl']?.toString() ?? '',
      triggeredByUserId: json['triggeredByUserId']?.toString() ?? '',
      scoringMethod: _mapFromJson(json['scoringMethod']),
    );
  }

  bool get exists => version.trim().isNotEmpty || filePath.trim().isNotEmpty;

  String get shortBlobId {
    final raw = sourceBlobId.trim();
    if (raw.length <= 12) {
      return raw;
    }
    return raw.substring(0, 12);
  }

  String get shortCommitSha {
    final raw = sourceCommitSha.trim();
    if (raw.length <= 12) {
      return raw;
    }
    return raw.substring(0, 12);
  }

  String get scoringMethodStatus {
    return scoringMethod['methodStatus']?.toString() ?? '';
  }

  bool get weightedOfficialMethodImplemented {
    return scoringMethod['weightedOfficialMethodImplemented'] is bool
        ? scoringMethod['weightedOfficialMethodImplemented'] as bool
        : false;
  }

  String get shortSourceSha256 {
    final raw = sourceSha256.trim();
    if (raw.length <= 16) {
      return raw;
    }
    return raw.substring(0, 16);
  }

  String get shortCanonicalSha256 {
    final raw = canonicalSha256.trim();
    if (raw.length <= 16) {
      return raw;
    }
    return raw.substring(0, 16);
  }

  static Map<String, dynamic> _mapFromJson(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.unmodifiable(value);
    }
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return const <String, dynamic>{};
  }

  static int _intFromJson(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

enum OfficialReferentialApiStatus { available, rejected, unreachable }

class OfficialReferentialApiResult {
  final OfficialReferentialApiStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final bool updateAvailable;
  final OfficialReferentialSummary? current;
  final OfficialReferentialSummary? remote;
  final Map<String, dynamic>? responseBody;

  const OfficialReferentialApiResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.updateAvailable,
    this.current,
    this.remote,
    this.responseBody,
  });

  bool get isAvailable => status == OfficialReferentialApiStatus.available;
}

class OfficialReferentialHistoryResult {
  final OfficialReferentialApiStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final List<OfficialReferentialSummary> history;
  final Map<String, dynamic>? responseBody;

  const OfficialReferentialHistoryResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.history,
    this.responseBody,
  });

  bool get isAvailable => status == OfficialReferentialApiStatus.available;
}
