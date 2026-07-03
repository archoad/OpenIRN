class DeviceEnrollmentRequest {
  final String tenantId;
  final String requestId;
  final String tenantDisplayName;
  final String deviceName;
  final String platform;
  final String requesterNote;
  final String status;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final String decidedByUserId;
  final String decidedByUserDisplayName;
  final String decisionNote;
  final String enrollmentId;

  const DeviceEnrollmentRequest({
    required this.tenantId,
    required this.requestId,
    this.tenantDisplayName = '',
    required this.deviceName,
    required this.platform,
    required this.requesterNote,
    required this.status,
    required this.requestedAt,
    required this.decidedAt,
    required this.decidedByUserId,
    this.decidedByUserDisplayName = '',
    required this.decisionNote,
    required this.enrollmentId,
  });

  bool get isPending => status.toLowerCase() == 'pending';

  String get displayName {
    final trimmed = deviceName.trim();
    return trimmed.isEmpty ? 'Terminal OpenIRN' : trimmed;
  }

  String get tenantLabel {
    final label = tenantDisplayName.trim();
    return label.isEmpty ? 'Espace de travail' : label;
  }

  String get decidedByLabel {
    final label = decidedByUserDisplayName.trim();
    return label.isEmpty ? 'Utilisateur' : label;
  }

  String get platformLabel {
    final normalized = platform.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Plateforme non renseignée';
    }
    switch (normalized) {
      case 'ios':
        return 'iOS';
      case 'ipados':
        return 'iPadOS';
      case 'android':
        return 'Android';
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      case 'web':
        return 'Web';
    }
    return platform.trim();
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'En attente';
      case 'approved':
        return 'Approuvée';
      case 'rejected':
        return 'Refusée';
      case 'consumed':
        return 'Consommée';
      default:
        return status.trim().isEmpty ? 'Inconnue' : status;
    }
  }

  factory DeviceEnrollmentRequest.fromJson(Map<String, dynamic> json) {
    return DeviceEnrollmentRequest(
      tenantId: json['tenantId']?.toString() ?? '',
      requestId: json['requestId']?.toString() ?? '',
      tenantDisplayName: json['tenantDisplayName']?.toString().trim() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      requesterNote: json['requesterNote']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      requestedAt: _parseDate(json['requestedAt']),
      decidedAt: _parseDate(json['decidedAt']),
      decidedByUserId: json['decidedByUserId']?.toString() ?? '',
      decidedByUserDisplayName:
          json['decidedByUserDisplayName']?.toString().trim() ?? '',
      decisionNote: json['decisionNote']?.toString() ?? '',
      enrollmentId: json['enrollmentId']?.toString() ?? '',
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
