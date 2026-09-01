class DeviceEnrollmentInvitation {
  final String tenantId;
  final String tenantDisplayName;
  final String enrollmentId;
  final String label;
  final String mode;
  final String status;
  final String createdByUserId;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int maxActiveDevices;
  final int activeDeviceCount;
  final int useCount;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;
  final String revokedByUserId;

  const DeviceEnrollmentInvitation({
    required this.tenantId,
    required this.tenantDisplayName,
    required this.enrollmentId,
    required this.label,
    required this.mode,
    required this.status,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
    required this.maxActiveDevices,
    required this.activeDeviceCount,
    required this.useCount,
    required this.lastUsedAt,
    required this.revokedAt,
    required this.revokedByUserId,
  });

  factory DeviceEnrollmentInvitation.fromJson(Map<String, dynamic> json) {
    int intValue(Object? value) {
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    DateTime? dateValue(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '')?.toUtc();

    return DeviceEnrollmentInvitation(
      tenantId: json['tenantId']?.toString() ?? '',
      tenantDisplayName: json['tenantDisplayName']?.toString() ?? '',
      enrollmentId: json['enrollmentId']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      mode: json['mode']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdByUserId: json['createdByUserId']?.toString() ?? '',
      createdAt: dateValue(json['createdAt']),
      expiresAt: dateValue(json['expiresAt']),
      maxActiveDevices: intValue(json['maxActiveDevices']),
      activeDeviceCount: intValue(json['activeDeviceCount']),
      useCount: intValue(json['useCount']),
      lastUsedAt: dateValue(json['lastUsedAt']),
      revokedAt: dateValue(json['revokedAt']),
      revokedByUserId: json['revokedByUserId']?.toString() ?? '',
    );
  }

  bool get isReusable => mode == 'reusable_until_revoked';
  bool get isActive => status == 'active' && revokedAt == null;
}
