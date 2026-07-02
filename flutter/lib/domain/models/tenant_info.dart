class TenantInfo {
  final String id;
  final String displayName;
  final String description;
  final bool permanent;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int userCount;
  final int activeUserCount;
  final int pilotCount;
  final int administratorCount;
  final int campaignCount;

  const TenantInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.permanent,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    required this.userCount,
    required this.activeUserCount,
    required this.pilotCount,
    required this.administratorCount,
    required this.campaignCount,
  });

  factory TenantInfo.fromJson(Map<String, dynamic> json) {
    return TenantInfo(
      id: json['tenantId']?.toString().trim().isNotEmpty == true
          ? json['tenantId'].toString().trim()
          : json['id']?.toString().trim() ?? '',
      displayName: json['displayName']?.toString().trim().isNotEmpty == true
          ? json['displayName'].toString().trim()
          : json['tenantId']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      permanent: json['permanent'] == true,
      isDefault: json['isDefault'] == true,
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toUtc(),
      updatedAt: DateTime.tryParse(
        json['updatedAt']?.toString() ?? '',
      )?.toUtc(),
      userCount: _intFromJson(json['userCount']),
      activeUserCount: _intFromJson(json['activeUserCount']),
      pilotCount: _intFromJson(json['pilotCount']),
      administratorCount: _intFromJson(json['administratorCount']),
      campaignCount: _intFromJson(json['campaignCount']),
    );
  }

  static int _intFromJson(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
