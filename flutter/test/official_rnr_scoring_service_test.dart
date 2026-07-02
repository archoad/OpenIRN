import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/services/official_rnr_scoring_service.dart';

void main() {
  test(
    'methodMetadata explicite que le score OpenIRN R/NR nest pas pondéré',
    () {
      expect(
        OfficialRnrScoringService.methodMetadata.methodStatus,
        'public_rnr_unweighted',
      );
      expect(
        OfficialRnrScoringService
            .methodMetadata
            .weightedOfficialMethodImplemented,
        isFalse,
      );
    },
  );

  test('computeSummary calcule R / (R + NR) et exclut les N.C.', () {
    final referential = _sampleReferential();
    const service = OfficialRnrScoringService();

    final summary = service.computeSummary(referential, {
      'RES-1.1': IrnAnswer.resilient,
      'RES-1.2': IrnAnswer.nonResilient,
      'RES-2.1': IrnAnswer.notAnswered,
    });

    expect(summary.totalCriteria, 3);
    expect(summary.answeredCriteria, 2);
    expect(summary.resilientCriteria, 1);
    expect(summary.nonResilientCriteria, 1);
    expect(summary.notAnsweredCriteria, 1);
    expect(summary.openIrnRnrScore, 50);
    expect(summary.officialScore, 50);
  });

  test('computeSummary retourne N/A si rien nest coté', () {
    final referential = _sampleReferential();
    const service = OfficialRnrScoringService();

    final summary = service.computeSummary(referential, const {});

    expect(summary.answeredCriteria, 0);
    expect(summary.officialScore, isNull);
    expect(summary.formattedOpenIrnRnrScore, 'N/A');
    expect(summary.formattedOfficialScore, 'N/A');
  });

  test('computeSummariesByPillar calcule un score distinct par pilier', () {
    final referential = _sampleReferential();
    const service = OfficialRnrScoringService();

    final summaries = service.computeSummariesByPillar(referential, {
      'RES-1.1': IrnAnswer.resilient,
      'RES-1.2': IrnAnswer.nonResilient,
      'RES-2.1': IrnAnswer.resilient,
    });

    expect(summaries[referential.pillars[0]]?.officialScore, 50);
    expect(summaries[referential.pillars[1]]?.officialScore, 100);
  });

  test('computeSummariesByScope regroupe organisation et actif numérique', () {
    final referential = _sampleReferential();
    const service = OfficialRnrScoringService();

    final summaries = service.computeSummariesByScope(referential, {
      'RES-1.1': IrnAnswer.resilient,
      'RES-1.2': IrnAnswer.nonResilient,
      'RES-2.1': IrnAnswer.resilient,
    });

    expect(summaries[CriterionScope.organization]?.totalCriteria, 2);
    expect(summaries[CriterionScope.asset]?.totalCriteria, 1);
    expect(summaries[CriterionScope.organization]?.officialScore, 50);
    expect(summaries[CriterionScope.asset]?.officialScore, 100);
  });
}

IrnReferential _sampleReferential() {
  return const IrnReferential(
    id: 'adri-irn-v1.1',
    version: 'v1.1',
    source: IrnSource(
      type: 'gitlab',
      url: 'https://gitlab.example',
      projectPath: 'project',
      defaultBranch: 'main',
      filePath: 'file.xlsx',
      license: 'CC BY-NC-ND 4.0',
    ),
    pillars: [
      IrnPillar(id: 'RES-1', code: 'RES-1', label: 'Stratégie'),
      IrnPillar(id: 'RES-2', code: 'RES-2', label: 'Économie'),
    ],
    criteria: [
      IrnCriterion(
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
      IrnCriterion(
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
      IrnCriterion(
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
    ],
  );
}
