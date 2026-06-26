import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';

class AssessmentQualityService {
  const AssessmentQualityService();

  AssessmentQualityReport buildReport({
    required IrnReferential referential,
    required Map<String, CriterionAnswer> criterionAnswers,
    LocalCampaign? campaign,
  }) {
    final activeCriteria = referential.criteria
        .where((criterion) => criterion.active)
        .toList(growable: false);

    final missingAnswers = <IrnCriterion>[];
    final missingJustifications = <AssessmentQualityIssue>[];
    final missingCampaignInformation = _missingCampaignInformation(campaign);
    var answeredCriteria = 0;
    var justifiedCriteria = 0;

    for (final criterion in activeCriteria) {
      final criterionAnswer = criterionAnswers[criterion.id] ??
          CriterionAnswer(
            criterionId: criterion.id,
            answer: IrnAnswer.notAnswered,
          );

      if (!criterionAnswer.answer.isCounted) {
        missingAnswers.add(criterion);
        continue;
      }

      answeredCriteria += 1;
      if (criterionAnswer.hasJustification) {
        justifiedCriteria += 1;
      } else {
        missingJustifications.add(
          AssessmentQualityIssue(
            criterion: criterion,
            answer: criterionAnswer.answer,
          ),
        );
      }
    }

    return AssessmentQualityReport(
      totalCriteria: activeCriteria.length,
      answeredCriteria: answeredCriteria,
      justifiedCriteria: justifiedCriteria,
      missingAnswers: List.unmodifiable(missingAnswers),
      missingJustifications: List.unmodifiable(missingJustifications),
      missingCampaignInformation: List.unmodifiable(missingCampaignInformation),
    );
  }

  List<CampaignInformationIssue> _missingCampaignInformation(
    LocalCampaign? campaign,
  ) {
    if (campaign == null) {
      return const <CampaignInformationIssue>[];
    }
    final info = campaign.information;
    return <CampaignInformationIssue>[
      if (!info.hasSystemName)
        const CampaignInformationIssue(
          field: 'systemName',
          label: 'Nom du système d’information',
        ),
      if (!info.hasSystemDescription)
        const CampaignInformationIssue(
          field: 'systemDescription',
          label: 'Description du système d’information',
        ),
      if (!info.hasProjectDirectorFirstName)
        const CampaignInformationIssue(
          field: 'projectDirectorFirstName',
          label: 'Prénom du directeur de projet',
        ),
      if (!info.hasProjectDirectorLastName)
        const CampaignInformationIssue(
          field: 'projectDirectorLastName',
          label: 'Nom du directeur de projet',
        ),
      if (!info.hasProjectDirectorEmail)
        const CampaignInformationIssue(
          field: 'projectDirectorEmail',
          label: 'Email du directeur de projet',
        ),
    ];
  }
}

class AssessmentQualityReport {
  final int totalCriteria;
  final int answeredCriteria;
  final int justifiedCriteria;
  final List<IrnCriterion> missingAnswers;
  final List<AssessmentQualityIssue> missingJustifications;
  final List<CampaignInformationIssue> missingCampaignInformation;

  const AssessmentQualityReport({
    required this.totalCriteria,
    required this.answeredCriteria,
    required this.justifiedCriteria,
    required this.missingAnswers,
    required this.missingJustifications,
    this.missingCampaignInformation = const <CampaignInformationIssue>[],
  });

  int get missingAnswerCount => missingAnswers.length;
  int get missingJustificationCount => missingJustifications.length;
  int get missingCampaignInformationCount => missingCampaignInformation.length;

  bool get isCampaignInformationComplete => missingCampaignInformation.isEmpty;

  bool get isReadyForReview =>
      totalCriteria > 0 &&
      missingAnswerCount == 0 &&
      missingJustificationCount == 0 &&
      missingCampaignInformationCount == 0;

  double get answerCompletionRate {
    if (totalCriteria == 0) {
      return 0;
    }
    return answeredCriteria / totalCriteria;
  }

  double get justificationCompletionRate {
    if (answeredCriteria == 0) {
      return 0;
    }
    return justifiedCriteria / answeredCriteria;
  }

  double get campaignInformationCompletionRate {
    const totalFields = 5;
    return (totalFields - missingCampaignInformationCount) / totalFields;
  }
}

class AssessmentQualityIssue {
  final IrnCriterion criterion;
  final IrnAnswer answer;

  const AssessmentQualityIssue({required this.criterion, required this.answer});
}

class CampaignInformationIssue {
  final String field;
  final String label;

  const CampaignInformationIssue({required this.field, required this.label});
}
