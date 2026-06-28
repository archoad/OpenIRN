import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/services/assessment_quality_service.dart';

void main() {
  test(
    'buildReport détecte les critères non cotés et les justifications manquantes',
    () {
      final referential = _sampleReferential();
      final report = const AssessmentQualityService().buildReport(
        referential: referential,
        criterionAnswers: const <String, CriterionAnswer>{
          'RES-1.1': CriterionAnswer(
            criterionId: 'RES-1.1',
            answer: IrnAnswer.resilient,
            justification: 'Gouvernance documentée.',
          ),
          'RES-1.2': CriterionAnswer(
            criterionId: 'RES-1.2',
            answer: IrnAnswer.nonResilient,
          ),
        },
      );

      expect(report.totalCriteria, 3);
      expect(report.answeredCriteria, 2);
      expect(report.justifiedCriteria, 1);
      expect(report.missingAnswerCount, 1);
      expect(report.missingAnswers.single.id, 'RES-2.1');
      expect(report.missingJustificationCount, 1);
      expect(report.missingJustifications.single.criterion.id, 'RES-1.2');
      expect(report.isReadyForReview, isFalse);
    },
  );

  test(
    'buildReport considère la campagne prête si tout est coté et justifié',
    () {
      final referential = _sampleReferential();
      final report = const AssessmentQualityService().buildReport(
        referential: referential,
        criterionAnswers: const <String, CriterionAnswer>{
          'RES-1.1': CriterionAnswer(
            criterionId: 'RES-1.1',
            answer: IrnAnswer.resilient,
            justification: 'Documenté.',
          ),
          'RES-1.2': CriterionAnswer(
            criterionId: 'RES-1.2',
            answer: IrnAnswer.nonResilient,
            justification: 'Plan de remédiation à ouvrir.',
          ),
          'RES-2.1': CriterionAnswer(
            criterionId: 'RES-2.1',
            answer: IrnAnswer.resilient,
            justification: 'Preuve disponible.',
          ),
        },
      );

      expect(report.missingAnswerCount, 0);
      expect(report.missingJustificationCount, 0);
      expect(report.answerCompletionRate, 1);
      expect(report.justificationCompletionRate, 1);
      expect(report.isReadyForReview, isTrue);
    },
  );

  test('buildReport ignore les critères inactifs', () {
    final referential = _sampleReferential(includeInactiveCriterion: true);
    final report = const AssessmentQualityService().buildReport(
      referential: referential,
      criterionAnswers: const <String, CriterionAnswer>{
        'RES-1.1': CriterionAnswer(
          criterionId: 'RES-1.1',
          answer: IrnAnswer.resilient,
          justification: 'Documenté.',
        ),
        'RES-1.2': CriterionAnswer(
          criterionId: 'RES-1.2',
          answer: IrnAnswer.nonResilient,
          justification: 'Documenté.',
        ),
        'RES-2.1': CriterionAnswer(
          criterionId: 'RES-2.1',
          answer: IrnAnswer.resilient,
          justification: 'Documenté.',
        ),
      },
    );

    expect(report.totalCriteria, 3);
    expect(report.isReadyForReview, isTrue);
  });

  test(
    'buildReport contrôle aussi les informations de campagne quand une campagne est fournie',
    () {
      final referential = _sampleReferential();
      final report = const AssessmentQualityService().buildReport(
        referential: referential,
        campaign: LocalCampaign.defaultForReferential(
          referentialId: 'adri-irn-v1.1',
          referentialVersion: 'v1.1',
        ),
        criterionAnswers: const <String, CriterionAnswer>{
          'RES-1.1': CriterionAnswer(
            criterionId: 'RES-1.1',
            answer: IrnAnswer.resilient,
            justification: 'Documenté.',
          ),
          'RES-1.2': CriterionAnswer(
            criterionId: 'RES-1.2',
            answer: IrnAnswer.nonResilient,
            justification: 'Documenté.',
          ),
          'RES-2.1': CriterionAnswer(
            criterionId: 'RES-2.1',
            answer: IrnAnswer.resilient,
            justification: 'Documenté.',
          ),
        },
      );

      expect(report.missingCampaignInformationCount, 5);
      expect(report.isReadyForReview, isFalse);
    },
  );

  test('buildReport accepte une campagne complète', () {
    final referential = _sampleReferential();
    final campaign =
        LocalCampaign.defaultForReferential(
          referentialId: 'adri-irn-v1.1',
          referentialVersion: 'v1.1',
        ).copyWith(
          information: const CampaignInformation(
            systemName: 'SI Comptable',
            systemDescription: 'Système comptable critique.',
            projectDirectorFirstName: 'Eva',
            projectDirectorLastName: 'Roux',
            projectDirectorEmail: 'eva.roux@example.test',
          ),
        );

    final report = const AssessmentQualityService().buildReport(
      referential: referential,
      campaign: campaign,
      criterionAnswers: const <String, CriterionAnswer>{
        'RES-1.1': CriterionAnswer(
          criterionId: 'RES-1.1',
          answer: IrnAnswer.resilient,
          justification: 'Documenté.',
        ),
        'RES-1.2': CriterionAnswer(
          criterionId: 'RES-1.2',
          answer: IrnAnswer.nonResilient,
          justification: 'Documenté.',
        ),
        'RES-2.1': CriterionAnswer(
          criterionId: 'RES-2.1',
          answer: IrnAnswer.resilient,
          justification: 'Documenté.',
        ),
      },
    );

    expect(report.missingCampaignInformationCount, 0);
    expect(report.campaignInformationCompletionRate, 1);
    expect(report.isReadyForReview, isTrue);
  });
}

IrnReferential _sampleReferential({bool includeInactiveCriterion = false}) {
  return IrnReferential(
    id: 'adri-irn-v1.1',
    version: 'v1.1',
    source: const IrnSource(
      type: 'gitlab',
      url: 'https://gitlab.example',
      projectPath: 'project',
      defaultBranch: 'main',
      filePath: 'file.xlsx',
      license: 'CC BY-NC-ND 4.0',
    ),
    pillars: const [
      IrnPillar(id: 'RES-1', code: 'RES-1', label: 'Stratégie'),
      IrnPillar(id: 'RES-2', code: 'RES-2', label: 'Économie'),
    ],
    criteria: [
      const IrnCriterion(
        id: 'RES-1.1',
        code: 'RES-1.1',
        sourceCode: 'RES-1.1',
        pillarId: 'RES-1',
        label: 'Critère 1',
        shortLabel: '',
        description: '',
        scope: CriterionScope.organization,
        sourceScope: 'Fonction ou organisation',
        answerMode: 'R_NR',
        regulatoryReferences: '',
        recommendations: '',
        active: true,
        source: CriterionSourceLocation(),
      ),
      const IrnCriterion(
        id: 'RES-1.2',
        code: 'RES-1.2',
        sourceCode: 'RES-1.2',
        pillarId: 'RES-1',
        label: 'Critère 2',
        shortLabel: '',
        description: '',
        scope: CriterionScope.organization,
        sourceScope: 'Fonction ou organisation',
        answerMode: 'R_NR',
        regulatoryReferences: '',
        recommendations: '',
        active: true,
        source: CriterionSourceLocation(),
      ),
      const IrnCriterion(
        id: 'RES-2.1',
        code: 'RES-2.1',
        sourceCode: 'RES-2.1',
        pillarId: 'RES-2',
        label: 'Critère 3',
        shortLabel: '',
        description: '',
        scope: CriterionScope.asset,
        sourceScope: 'Actif numérique',
        answerMode: 'R_NR',
        regulatoryReferences: '',
        recommendations: '',
        active: true,
        source: CriterionSourceLocation(),
      ),
      if (includeInactiveCriterion)
        const IrnCriterion(
          id: 'RES-2.2',
          code: 'RES-2.2',
          sourceCode: 'RES-2.2',
          pillarId: 'RES-2',
          label: 'Critère inactif',
          shortLabel: '',
          description: '',
          scope: CriterionScope.asset,
          sourceScope: 'Actif numérique',
          answerMode: 'R_NR',
          regulatoryReferences: '',
          recommendations: '',
          active: false,
          source: CriterionSourceLocation(),
        ),
    ],
  );
}
