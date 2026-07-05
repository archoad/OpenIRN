import 'dart:convert';

import '../models/app_user.dart';
import '../models/criterion_assignment.dart';
import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_activity_event.dart';
import '../models/local_campaign.dart';
import 'official_rnr_scoring_service.dart';

class AssessmentExportService {
  const AssessmentExportService({
    this.scoringService = const OfficialRnrScoringService(),
  });

  final OfficialRnrScoringService scoringService;

  String buildPrettyJson({
    required IrnReferential referential,
    required Map<String, CriterionAnswer> criterionAnswers,
    LocalCampaign? campaign,
    List<LocalActivityEvent> activityEvents = const <LocalActivityEvent>[],
    List<AppUser> users = const <AppUser>[],
    List<CriterionAssignment> assignments = const <CriterionAssignment>[],
    DateTime? exportedAt,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(
      buildPayload(
        referential: referential,
        campaign: campaign,
        criterionAnswers: criterionAnswers,
        activityEvents: activityEvents,
        users: users,
        assignments: assignments,
        exportedAt: exportedAt,
      ),
    );
  }

  Map<String, dynamic> buildPayload({
    required IrnReferential referential,
    required Map<String, CriterionAnswer> criterionAnswers,
    LocalCampaign? campaign,
    List<LocalActivityEvent> activityEvents = const <LocalActivityEvent>[],
    List<AppUser> users = const <AppUser>[],
    List<CriterionAssignment> assignments = const <CriterionAssignment>[],
    DateTime? exportedAt,
  }) {
    final exportedAtUtc = (exportedAt ?? DateTime.now()).toUtc();
    final answers = _answersFromCriterionAnswers(criterionAnswers);
    final maturitySummary = campaign?.information.isAssetScoped == true
        ? scoringService.computeSystemMaturity(
            referential,
            campaign!,
            criterionAnswers,
          )
        : null;
    final globalSummary =
        maturitySummary?.aggregateSummary ??
        scoringService.computeSummary(referential, answers);
    final pillarSummaries =
        maturitySummary?.aggregatePillarSummaries ??
        scoringService.computeSummariesByPillar(referential, answers);
    final scopeSummaries = maturitySummary == null
        ? scoringService.computeSummariesByScope(referential, answers)
        : scoringService.computeAssetScopedSummariesByScope(
            referential,
            campaign!,
            criterionAnswers,
          );

    return <String, dynamic>{
      'schemaVersion': 7,
      'type': 'openirn.localAssessmentExport',
      'application': 'OpenIRN',
      'exportedAt': exportedAtUtc.toIso8601String(),
      if (campaign != null)
        'campaign': <String, dynamic>{
          'id': campaign.id,
          'name': campaign.name,
          'description': campaign.description,
          'system': <String, dynamic>{
            'name': campaign.information.systemName,
            'description': campaign.information.systemDescription,
          },
          'projectDirector': <String, dynamic>{
            'firstName': campaign.information.projectDirectorFirstName,
            'lastName': campaign.information.projectDirectorLastName,
            'email': campaign.information.projectDirectorEmail,
          },
          'status': campaign.status.jsonValue,
          'statusLabel': campaign.status.label,
          'createdAt': campaign.createdAt.toUtc().toIso8601String(),
          'updatedAt': campaign.updatedAt.toUtc().toIso8601String(),
          'statusUpdatedAt': campaign.statusUpdatedAt.toUtc().toIso8601String(),
        },
      'referential': <String, dynamic>{
        'id': referential.id,
        'version': referential.version,
        'license': referential.license,
        'sourceUrl': referential.sourceUrl,
        'sourceFilePath': referential.source.filePath,
        'sourceCommitSha': referential.source.commitSha,
        'sourceBlobId': referential.source.blobId,
        'checksumSha256': referential.checksumSha256,
      },
      'scoring': <String, dynamic>{
        ...referential.scoring.toJson(),
        'global': _summaryToJson(
          globalSummary,
          maturityScore: maturitySummary?.maturityScore,
        ),
        if (maturitySummary != null)
          'maturity': _maturityToJson(maturitySummary),
        'byPillar': <Map<String, dynamic>>[
          for (final entry in pillarSummaries.entries)
            <String, dynamic>{
              'pillarId': entry.key.id,
              'pillarCode': entry.key.code,
              'pillarLabel': entry.key.label,
              ..._summaryToJson(entry.value),
            },
        ],
        'byScope': <Map<String, dynamic>>[
          for (final entry in scopeSummaries.entries)
            <String, dynamic>{
              'scope': entry.key.jsonValue,
              'scopeLabel': entry.key.label,
              ..._summaryToJson(entry.value),
            },
        ],
      },
      'collaboration': <String, dynamic>{
        'mode': 'local_users_and_assignments',
        'users': <Map<String, dynamic>>[
          for (final user in users) _userToJson(user),
        ],
        'assignments': <Map<String, dynamic>>[
          for (final assignment in assignments) _assignmentToJson(assignment),
        ],
      },
      'activityLog': <String, dynamic>{
        'included': true,
        'eventCount': activityEvents.length,
        'retentionPolicy': 'local_last_300_events_per_campaign',
        'events': <Map<String, dynamic>>[
          for (final event in activityEvents) _activityEventToJson(event),
        ],
      },
      'answers': _answersToJson(
        referential: referential,
        campaign: campaign,
        criterionAnswers: criterionAnswers,
      ),
    };
  }

  Map<String, IrnAnswer> _answersFromCriterionAnswers(
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    return <String, IrnAnswer>{
      for (final entry in criterionAnswers.entries)
        entry.key: entry.value.answer,
    };
  }

  Map<String, dynamic> _summaryToJson(
    IrnScoreSummary summary, {
    double? maturityScore,
  }) {
    final effectiveScore = maturityScore ?? summary.openIrnScore;
    return <String, dynamic>{
      'totalCriteria': summary.totalCriteria,
      'answeredCriteria': summary.answeredCriteria,
      'notConcernedCriteria': summary.notConcernedCriteria,
      'nonResilientCriteria': summary.nonResilientCriteria,
      'intentionCriteria': summary.intentionCriteria,
      'mediumCriteria': summary.mediumCriteria,
      'resultCriteria': summary.resultCriteria,
      'notAnsweredCriteria': summary.notAnsweredCriteria,
      'scoredCriteria': summary.scoredCriteria,
      'scorePointsTotal': summary.scorePointsTotal,
      'completionRate': _round(summary.completionRate),
      'openIrnScore': effectiveScore == null ? null : _round(effectiveScore),
      'openIrnRnrScore': effectiveScore == null ? null : _round(effectiveScore),
      'officialScore': effectiveScore == null ? null : _round(effectiveScore),
      if (maturityScore != null)
        'assetMaturityWeightedScore': _round(maturityScore),
    };
  }

  Map<String, dynamic> _maturityToJson(IrnSystemMaturitySummary maturity) {
    return <String, dynamic>{
      'formula': 'EXP(SUM(D*LN(E))/SUM(D))',
      'score': maturity.maturityScore == null
          ? null
          : _round(maturity.maturityScore!),
      'scoredAssetCount': maturity.scoredAssetCount,
      'totalAssetCount': maturity.totalAssetCount,
      'criticalityWeightTotal': maturity.maturityWeightTotal,
      'assetScores': <Map<String, dynamic>>[
        for (final assetScore in maturity.assetScores)
          <String, dynamic>{
            'assetId': assetScore.asset.id,
            'assetName': assetScore.asset.displayLabel,
            'criticality': assetScore.criticalityWeight,
            'score': assetScore.maturityScore == null
                ? null
                : _round(assetScore.maturityScore!),
            'scoredPillarCount': assetScore.scoredPillarCount,
            'totalPillarCount': assetScore.totalPillarCount,
            'completionRate': _round(
              assetScore.aggregateSummary.completionRate,
            ),
          },
      ],
    };
  }

  Map<String, dynamic> _userToJson(AppUser user) {
    return <String, dynamic>{
      'id': user.id,
      'firstName': user.firstName,
      'lastName': user.lastName,
      'email': user.email,
      'role': user.role.jsonValue,
      'roleLabel': user.role.label,
      'active': user.active,
    };
  }

  Map<String, dynamic> _assignmentToJson(CriterionAssignment assignment) {
    return <String, dynamic>{
      'id': assignment.id,
      'criterionId': assignment.criterionId,
      'userId': assignment.userId,
      if (assignment.assignedByUserId.trim().isNotEmpty)
        'assignedByUserId': assignment.assignedByUserId,
      'createdAt': assignment.createdAt.toUtc().toIso8601String(),
      'updatedAt': assignment.updatedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _activityEventToJson(LocalActivityEvent event) {
    return <String, dynamic>{
      'id': event.id,
      'type': event.type.jsonValue,
      'typeLabel': event.type.label,
      'title': event.title,
      'description': event.description,
      if (event.criterionId != null) 'criterionId': event.criterionId,
      if (event.fromValue != null) 'fromValue': event.fromValue,
      if (event.toValue != null) 'toValue': event.toValue,
      'createdAt': event.createdAt.toUtc().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _answersToJson({
    required IrnReferential referential,
    required LocalCampaign? campaign,
    required Map<String, CriterionAnswer> criterionAnswers,
  }) {
    final activeCriteria = referential.criteria
        .where((criterion) => criterion.active)
        .toList(growable: false);
    if (campaign?.information.isAssetScoped != true) {
      return <Map<String, dynamic>>[
        for (final criterion in activeCriteria)
          _answerToJson(
            criterion: criterion,
            criterionAnswer:
                criterionAnswers[criterion.id] ??
                CriterionAnswer(
                  criterionId: criterion.id,
                  answer: IrnAnswer.notAnswered,
                ),
          ),
      ];
    }

    final assets = campaign!.information.assets;
    return <Map<String, dynamic>>[
      for (final asset in assets)
        for (final criterion in activeCriteria)
          _answerToJson(
            criterion: criterion,
            asset: asset,
            criterionAnswer:
                criterionAnswers['asset:${asset.id}:criterion:${criterion.id}'] ??
                CriterionAnswer(
                  criterionId: 'asset:${asset.id}:criterion:${criterion.id}',
                  answer: IrnAnswer.notAnswered,
                ),
          ),
    ];
  }

  Map<String, dynamic> _answerToJson({
    required IrnCriterion criterion,
    required CriterionAnswer criterionAnswer,
    CampaignInformationAsset? asset,
  }) {
    final justification = criterionAnswer.justification.trim();

    return <String, dynamic>{
      if (asset != null) 'assetId': asset.id,
      if (asset != null) 'assetName': asset.displayLabel,
      if (asset != null) 'assetCriticality': asset.criticalityWeight,
      'criterionId': criterion.id,
      'criterionCode': criterion.code,
      'sourceCode': criterion.sourceCode,
      'pillarId': criterion.pillarId,
      'scope': criterion.scope.jsonValue,
      'scopeLabel': criterion.scope.label,
      'answer': _officialAnswerValue(criterionAnswer.answer),
      'answerLabel': criterionAnswer.answer.longLabel,
      'isAnswered': criterionAnswer.answer.isAnswered,
      'isScoredInScore': criterionAnswer.answer.isScored,
      if (criterionAnswer.answer.scoreValue != null)
        'answerScore': criterionAnswer.answer.scoreValue,
      'justification': justification,
      'hasJustification': justification.isNotEmpty,
    };
  }

  String _officialAnswerValue(IrnAnswer answer) {
    switch (answer) {
      case IrnAnswer.notConcerned:
        return 'NC';
      case IrnAnswer.nonResilient:
        return 'NR';
      case IrnAnswer.intention:
        return 'INTENTION';
      case IrnAnswer.medium:
        return 'MOYEN';
      case IrnAnswer.result:
        return 'RESULTAT';
      case IrnAnswer.notAnswered:
        return 'NON_RENSEIGNE';
    }
  }

  double _round(double value) {
    return double.parse(value.toStringAsFixed(4));
  }
}
