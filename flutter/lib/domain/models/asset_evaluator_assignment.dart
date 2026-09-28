class AssetEvaluatorAssignment {
  final String id;
  final String referentialId;
  final String campaignId;
  final String assetId;
  final String userId;
  final String assignedByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssetEvaluatorAssignment({
    required this.id,
    required this.referentialId,
    required this.campaignId,
    required this.assetId,
    required this.userId,
    required this.assignedByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AssetEvaluatorAssignment.create({
    required String referentialId,
    required String campaignId,
    required String assetId,
    required String userId,
    String assignedByUserId = '',
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return AssetEvaluatorAssignment(
      id: 'asset-assignment-${_safeIdPart(assetId)}',
      referentialId: referentialId,
      campaignId: campaignId,
      assetId: assetId,
      userId: userId,
      assignedByUserId: assignedByUserId.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory AssetEvaluatorAssignment.fromJson(Map<String, dynamic> json) {
    final createdAt =
        _parseDate(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAt = _parseDate(json['updatedAt']) ?? createdAt;
    return AssetEvaluatorAssignment(
      id: json['id']?.toString() ?? '',
      referentialId: json['referentialId']?.toString() ?? '',
      campaignId: json['campaignId']?.toString() ?? '',
      assetId: json['assetId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      assignedByUserId: json['assignedByUserId']?.toString() ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'referentialId': referentialId,
      'campaignId': campaignId,
      'assetId': assetId,
      'userId': userId,
      if (assignedByUserId.trim().isNotEmpty)
        'assignedByUserId': assignedByUserId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  static String _safeIdPart(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
