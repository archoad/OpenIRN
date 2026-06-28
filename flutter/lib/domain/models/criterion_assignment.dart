class CriterionAssignment {
  final String id;
  final String referentialId;
  final String campaignId;
  final String criterionId;
  final String userId;
  final String assignedByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CriterionAssignment({
    required this.id,
    required this.referentialId,
    required this.campaignId,
    required this.criterionId,
    required this.userId,
    required this.assignedByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CriterionAssignment.create({
    required String referentialId,
    required String campaignId,
    required String criterionId,
    required String userId,
    String assignedByUserId = '',
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return CriterionAssignment(
      id: _buildId(
        referentialId: referentialId,
        campaignId: campaignId,
        criterionId: criterionId,
      ),
      referentialId: referentialId,
      campaignId: campaignId,
      criterionId: criterionId,
      userId: userId,
      assignedByUserId: assignedByUserId.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory CriterionAssignment.fromJson(Map<String, dynamic> json) {
    final createdAt =
        _parseDate(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAt = _parseDate(json['updatedAt']) ?? createdAt;
    return CriterionAssignment(
      id: json['id']?.toString() ?? '',
      referentialId: json['referentialId']?.toString() ?? '',
      campaignId: json['campaignId']?.toString() ?? '',
      criterionId: json['criterionId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      assignedByUserId: json['assignedByUserId']?.toString() ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  CriterionAssignment copyWith({
    String? userId,
    String? assignedByUserId,
    DateTime? updatedAt,
  }) {
    return CriterionAssignment(
      id: id,
      referentialId: referentialId,
      campaignId: campaignId,
      criterionId: criterionId,
      userId: userId ?? this.userId,
      assignedByUserId: assignedByUserId ?? this.assignedByUserId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'referentialId': referentialId,
      'campaignId': campaignId,
      'criterionId': criterionId,
      'userId': userId,
      if (assignedByUserId.trim().isNotEmpty)
        'assignedByUserId': assignedByUserId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  static String _buildId({
    required String referentialId,
    required String campaignId,
    required String criterionId,
  }) {
    return 'assignment-${_safeIdPart(referentialId)}-${_safeIdPart(campaignId)}-${_safeIdPart(criterionId)}';
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
