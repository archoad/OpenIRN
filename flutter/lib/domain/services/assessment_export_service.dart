import 'dart:convert';

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
    DateTime? exportedAt,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(
      buildPayload(
        referential: referential,
        campaign: campaign,
        criterionAnswers: criterionAnswers,
        activityEvents: activityEvents,
        exportedAt: exportedAt,
      ),
    );
  }

  Map<String, dynamic> buildPayload({
    required IrnReferential referential,
    required Map<String, CriterionAnswer> criterionAnswers,
    LocalCampaign? campaign,
    List<LocalActivityEvent> activityEvents = const <LocalActivityEvent>[],
    DateTime? exportedAt,
  }) {
    final exportedAtUtc = (exportedAt ?? DateTime.now()).toUtc();
    final answers = _answersFromCriterionAnswers(criterionAnswers);
    final globalSummary = scoringService.computeSummary(referential, answers);
    final pillarSummaries =
        scoringService.computeSummariesByPillar(referential, answers);
    final scopeSummaries =
        scoringService.computeSummariesByScope(referential, answers);

    return <String, dynamic>{
      'schemaVersion': 5,
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
        'checksumSha256': referential.checksumSha256,
      },
      'scoring': <String, dynamic>{
        'method': 'R / (R + NR) * 100',
        'notAnsweredPolicy': 'excluded_from_score_included_in_completion',
        'global': _summaryToJson(globalSummary),
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
      'activityLog': <String, dynamic>{
        'included': true,
        'eventCount': activityEvents.length,
        'retentionPolicy': 'local_last_300_events_per_campaign',
        'events': <Map<String, dynamic>>[
          for (final event in activityEvents) _activityEventToJson(event),
        ],
      },
      'answers': <Map<String, dynamic>>[
        for (final criterion in referential.criteria)
          if (criterion.active)
            _answerToJson(
              criterion: criterion,
              criterionAnswer: criterionAnswers[criterion.id] ??
                  CriterionAnswer(
                    criterionId: criterion.id,
                    answer: IrnAnswer.notAnswered,
                  ),
            ),
      ],
    };
  }

  Map<String, IrnAnswer> _answersFromCriterionAnswers(
      Map<String, CriterionAnswer> criterionAnswers) {
    return <String, IrnAnswer>{
      for (final entry in criterionAnswers.entries)
        entry.key: entry.value.answer,
    };
  }

  Map<String, dynamic> _summaryToJson(IrnScoreSummary summary) {
    return <String, dynamic>{
      'totalCriteria': summary.totalCriteria,
      'answeredCriteria': summary.answeredCriteria,
      'resilientCriteria': summary.resilientCriteria,
      'nonResilientCriteria': summary.nonResilientCriteria,
      'notAnsweredCriteria': summary.notAnsweredCriteria,
      'completionRate': _round(summary.completionRate),
      'officialScore':
          summary.officialScore == null ? null : _round(summary.officialScore!),
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

  Map<String, dynamic> _answerToJson({
    required IrnCriterion criterion,
    required CriterionAnswer criterionAnswer,
  }) {
    final justification = criterionAnswer.justification.trim();

    return <String, dynamic>{
      'criterionId': criterion.id,
      'criterionCode': criterion.code,
      'sourceCode': criterion.sourceCode,
      'pillarId': criterion.pillarId,
      'scope': criterion.scope.jsonValue,
      'scopeLabel': criterion.scope.label,
      'answer': _officialAnswerValue(criterionAnswer.answer),
      'answerLabel': criterionAnswer.answer.longLabel,
      'isCountedInScore': criterionAnswer.answer.isCounted,
      'justification': justification,
      'hasJustification': justification.isNotEmpty,
    };
  }

  String _officialAnswerValue(IrnAnswer answer) {
    switch (answer) {
      case IrnAnswer.resilient:
        return 'R';
      case IrnAnswer.nonResilient:
        return 'NR';
      case IrnAnswer.notAnswered:
        return 'NC';
    }
  }

  double _round(double value) {
    return double.parse(value.toStringAsFixed(4));
  }
}
