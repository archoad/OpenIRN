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

  bool get usesSessionToken => apiToken.trim().startsWith('ost_');

  bool get usesLegacyBearerToken =>
      hasApiToken && !usesDeviceToken && !usesSessionToken;

  String get authorizationModeLabel {
    if (!isConfigured) {
      return 'Terminal non autorisé';
    }
    if (!hasApiToken) {
      return 'Terminal autorisé, session absente';
    }
    if (usesSessionToken) {
      return 'Session serveur en mémoire';
    }
    if (usesDeviceToken) {
      return 'Jeton terminal de transition';
    }
    return 'Bearer de transition en mémoire';
  }

  String get authorizationModeDescription {
    if (!isConfigured) {
      return 'Ce terminal doit être autorisé avec un code d’appairage.';
    }
    if (!hasApiToken) {
      return 'Aucun secret n’est stocké localement. Déverrouille OpenIRN avec ton profil et ton code personnel pour ouvrir une session courte.';
    }
    if (usesSessionToken) {
      return 'La session serveur est conservée uniquement en mémoire et sera perdue à la fermeture de l’application.';
    }
    if (usesDeviceToken) {
      return 'Ce terminal utilise encore un ancien jeton terminal. Il ne sera plus réenregistré localement.';
    }
    return 'Bearer utilisé uniquement pour cette session courante. Il ne sera pas stocké localement.';
  }

  bool get isConfigured =>
      enabled && hasApiBaseUrl && hasTenantId && hasDeviceId;

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
