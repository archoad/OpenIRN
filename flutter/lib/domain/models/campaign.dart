enum CampaignStatus {
  draft,
  assignment,
  assessment,
  review,
  validated,
  archived,
}

enum TargetType { organization, businessFunction, criticalSystem, asset }

enum AssignmentStatus { todo, inProgress, submitted, validated, rejected }

class Campaign {
  final String id;
  final String name;
  final String referentialId;
  final CampaignStatus status;
  final DateTime createdAt;

  const Campaign({
    required this.id,
    required this.name,
    required this.referentialId,
    required this.status,
    required this.createdAt,
  });
}

class Assignment {
  final String id;
  final String campaignId;
  final TargetType targetType;
  final String targetId;
  final String criterionId;
  final String assigneeId;
  final AssignmentStatus status;

  const Assignment({
    required this.id,
    required this.campaignId,
    required this.targetType,
    required this.targetId,
    required this.criterionId,
    required this.assigneeId,
    required this.status,
  });
}
