import 'campaign.dart';

enum OfficialAnswer { resilient, nonResilient, notConcerned }

enum InternalMaturityLevel {
  nonResilient,
  intention,
  moyen,
  resultat,
  notConcerned,
}

enum ConfidenceLevel { low, medium, high }

enum EvaluationStatus { draft, submitted, validated, rejected }

class Evaluation {
  final String id;
  final String campaignId;
  final TargetType targetType;
  final String targetId;
  final String criterionId;
  final OfficialAnswer? officialAnswer;
  final InternalMaturityLevel? internalMaturityLevel;
  final double? internalScore;
  final String justification;
  final ConfidenceLevel? confidence;
  final EvaluationStatus status;
  final int version;
  final DateTime updatedAt;

  const Evaluation({
    required this.id,
    required this.campaignId,
    required this.targetType,
    required this.targetId,
    required this.criterionId,
    required this.status,
    required this.version,
    required this.updatedAt,
    this.officialAnswer,
    this.internalMaturityLevel,
    this.internalScore,
    this.justification = '',
    this.confidence,
  });

  bool get isEditable =>
      status == EvaluationStatus.draft || status == EvaluationStatus.rejected;
  bool get hasRequiredJustification => justification.trim().isNotEmpty;
}
