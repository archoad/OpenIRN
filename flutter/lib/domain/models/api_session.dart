class ApiSessionInfo {
  final String sessionId;
  final String tenantId;
  final String deviceId;
  final String deviceName;
  final String devicePlatform;
  final String userId;
  final String userDisplayName;
  final String userEmail;
  final String userRole;
  final String status;
  final bool isCurrentSession;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  const ApiSessionInfo({
    required this.sessionId,
    required this.tenantId,
    required this.deviceId,
    required this.deviceName,
    required this.devicePlatform,
    required this.userId,
    required this.userDisplayName,
    required this.userEmail,
    required this.userRole,
    required this.status,
    required this.isCurrentSession,
    required this.createdAt,
    required this.expiresAt,
    required this.lastSeenAt,
    required this.revokedAt,
  });

  factory ApiSessionInfo.fromJson(Map<String, dynamic> json) {
    return ApiSessionInfo(
      sessionId: json['sessionId']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
      devicePlatform: json['devicePlatform']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userDisplayName: json['userDisplayName']?.toString() ?? '',
      userEmail: json['userEmail']?.toString() ?? '',
      userRole: json['userRole']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      isCurrentSession: json['isCurrentSession'] == true,
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toUtc(),
      expiresAt: DateTime.tryParse(
        json['expiresAt']?.toString() ?? '',
      )?.toUtc(),
      lastSeenAt: DateTime.tryParse(
        json['lastSeenAt']?.toString() ?? '',
      )?.toUtc(),
      revokedAt: DateTime.tryParse(
        json['revokedAt']?.toString() ?? '',
      )?.toUtc(),
    );
  }

  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';
  bool get isExpired => status == 'expired';

  String get statusLabel {
    if (isActive) {
      return 'Active';
    }
    if (isRevoked) {
      return 'Révoquée';
    }
    if (isExpired) {
      return 'Expirée';
    }
    return status.isEmpty ? 'Inconnue' : status;
  }

  String get displayUser {
    if (userDisplayName.trim().isNotEmpty) {
      return userDisplayName.trim();
    }
    if (userEmail.trim().isNotEmpty) {
      return userEmail.trim();
    }
    return userId;
  }

  String get displayDevice {
    if (deviceName.trim().isNotEmpty) {
      return deviceName.trim();
    }
    return deviceId;
  }
}
