class SyncConfiguration {
  static const fixedApiBaseUrl = 'https://www.archoad.io/api';
  static const defaultTenantId = 'archoad';

  final String apiBaseUrl;
  final String tenantId;
  final String deviceId;
  final bool enabled;
  final String apiToken;
  final DateTime updatedAt;

  const SyncConfiguration({
    required this.apiBaseUrl,
    required this.tenantId,
    required this.deviceId,
    required this.enabled,
    required this.apiToken,
    required this.updatedAt,
  });

  factory SyncConfiguration.empty({String deviceId = '', DateTime? now}) {
    return SyncConfiguration(
      apiBaseUrl: fixedApiBaseUrl,
      tenantId: defaultTenantId,
      deviceId: deviceId,
      enabled: false,
      apiToken: '',
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
  }

  bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;
  bool get hasTenantId => tenantId.trim().isNotEmpty;
  bool get hasDeviceId => deviceId.trim().isNotEmpty;
  bool get hasApiToken => apiToken.trim().isNotEmpty;

  bool get usesDeviceToken => apiToken.trim().startsWith('odt_');

  bool get usesLegacyBearerToken => hasApiToken && !usesDeviceToken;

  String get authorizationModeLabel {
    if (!hasApiToken) {
      return 'Non autorisé';
    }
    if (usesDeviceToken) {
      return 'Jeton terminal';
    }
    return 'Bearer de transition';
  }

  String get authorizationModeDescription {
    if (!hasApiToken) {
      return 'Ce terminal doit être autorisé avec un code d’appairage.';
    }
    if (usesDeviceToken) {
      return 'Ce terminal utilise un jeton individuel révocable côté serveur.';
    }
    return 'Ce terminal utilise encore le bearer global historique. Réautorise-le dès que possible avec un code d’appairage.';
  }

  bool get isConfigured =>
      enabled && hasApiBaseUrl && hasTenantId && hasDeviceId && hasApiToken;

  String get maskedApiToken {
    final token = apiToken.trim();
    if (token.isEmpty) {
      return 'Non configuré';
    }
    if (token.length <= 8) {
      return '••••';
    }
    return '${token.substring(0, 4)}••••${token.substring(token.length - 4)}';
  }

  SyncConfiguration copyWith({
    String? apiBaseUrl,
    String? tenantId,
    String? deviceId,
    bool? enabled,
    String? apiToken,
    DateTime? updatedAt,
  }) {
    return SyncConfiguration(
      apiBaseUrl: normalizeApiBaseUrl(apiBaseUrl ?? this.apiBaseUrl),
      tenantId: (tenantId ?? this.tenantId).trim(),
      deviceId: (deviceId ?? this.deviceId).trim(),
      enabled: enabled ?? this.enabled,
      apiToken: (apiToken ?? this.apiToken).trim(),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory SyncConfiguration.fromJson(Map<String, dynamic> json) {
    return SyncConfiguration(
      apiBaseUrl: fixedApiBaseUrl,
      tenantId: json['tenantId']?.toString().trim().isNotEmpty == true
          ? json['tenantId'].toString().trim()
          : defaultTenantId,
      deviceId: json['deviceId']?.toString().trim() ?? '',
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      apiToken: json['apiToken']?.toString().trim() ?? '',
      updatedAt:
          _parseDate(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'apiBaseUrl': apiBaseUrl,
      'tenantId': tenantId,
      'deviceId': deviceId,
      'enabled': enabled,
      'apiToken': apiToken,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toPublicJson() {
    return <String, dynamic>{
      'apiBaseUrl': apiBaseUrl,
      'tenantId': tenantId,
      'deviceId': deviceId,
      'enabled': enabled,
      'apiTokenConfigured': hasApiToken,
      'apiTokenMasked': maskedApiToken,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  static String normalizeApiBaseUrl(String value) {
    final trimmed = value.trim().isEmpty ? fixedApiBaseUrl : value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.replaceAll(RegExp(r'/+$'), '');
    }
    return trimmed;
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
