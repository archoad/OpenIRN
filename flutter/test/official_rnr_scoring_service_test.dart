import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/services/official_rnr_scoring_service.dart';

void main() {
  test('methodMetadata explicite la maturité IRN pondérée par actifs', () {
    expect(
      OfficialRnrScoringService.methodMetadata.methodStatus,
      'irn_asset_maturity_weighted_geometric_v1',
    );
    expect(
      OfficialRnrScoringService
          .methodMetadata
          .weightedOfficialMethodImplemented,
      isTrue,
    );
  });

  test(
    'computeSummary calcule la moyenne des niveaux notés et exclut les N.C.',
    () {
      final referential = _sampleReferential();
      const service = OfficialRnrScoringService();

      final summary = service.computeSummary(referential, {
        'RES-1.1': IrnAnswer.result,
        'RES-1.2': IrnAnswer.nonResilient,
        'RES-2.1': IrnAnswer.notAnswered,
      });

      expect(summary.totalCriteria, 3);
      expect(summary.answeredCriteria, 2);
      expect(summary.resilientCriteria, 1);
      expect(summary.nonResilientCriteria, 1);
      expect(summary.notAnsweredCriteria, 1);
      expect(summary.openIrnRnrScore, 52.5);
      expect(summary.officialScore, 52.5);
    },
  );

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
      'RES-1.1': IrnAnswer.result,
      'RES-1.2': IrnAnswer.nonResilient,
      'RES-2.1': IrnAnswer.result,
    });

    expect(summaries[referential.pillars[0]]?.officialScore, 52.5);
    expect(summaries[referential.pillars[1]]?.officialScore, 95);
  });

  test('computeSummariesByScope regroupe organisation et actif numérique', () {
    final referential = _sampleReferential();
    const service = OfficialRnrScoringService();

    final summaries = service.computeSummariesByScope(referential, {
      'RES-1.1': IrnAnswer.result,
      'RES-1.2': IrnAnswer.nonResilient,
      'RES-2.1': IrnAnswer.result,
    });

    expect(summaries[CriterionScope.organization]?.totalCriteria, 2);
    expect(summaries[CriterionScope.asset]?.totalCriteria, 1);
    expect(summaries[CriterionScope.organization]?.officialScore, 52.5);
    expect(summaries[CriterionScope.asset]?.officialScore, 95);
  });

  test(
    'computeSystemMaturity applique la moyenne géométrique pondérée par la criticité',
    () {
      final referential = _sampleReferential();
      const service = OfficialRnrScoringService();
      final campaign = LocalCampaign(
        id: 'campaign-asset-scope',
        referentialId: 'adri-irn-v1.1',
        name: 'Campagne SI',
        information: CampaignInformation(
          systemName: 'SI critique',
          informationSystemId: 'system-1',
          assets: [
            CampaignInformationAsset(
              id: 'asset-vital',
              name: 'Actif vital',
              criticality: '4',
            ),
            CampaignInformationAsset(
              id: 'asset-standard',
              name: 'Actif standard',
              criticality: '1',
            ),
          ],
        ),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        statusUpdatedAt: DateTime.utc(2026),
      );

      final maturity = service.computeSystemMaturity(
        referential,
        campaign,
        const <String, CriterionAnswer>{
          'asset:asset-vital:criterion:RES-1.1': CriterionAnswer(
            criterionId: 'asset:asset-vital:criterion:RES-1.1',
            answer: IrnAnswer.result,
          ),
          'asset:asset-vital:criterion:RES-2.1': CriterionAnswer(
            criterionId: 'asset:asset-vital:criterion:RES-2.1',
            answer: IrnAnswer.result,
          ),
          'asset:asset-standard:criterion:RES-1.1': CriterionAnswer(
            criterionId: 'asset:asset-standard:criterion:RES-1.1',
            answer: IrnAnswer.nonResilient,
          ),
          'asset:asset-standard:criterion:RES-2.1': CriterionAnswer(
            criterionId: 'asset:asset-standard:criterion:RES-2.1',
            answer: IrnAnswer.nonResilient,
          ),
        },
      );

      expect(maturity.scoredAssetCount, 2);
      expect(maturity.maturityWeightTotal, 5);
      expect(maturity.assetScores[0].maturityScore, closeTo(95, 0.001));
      expect(maturity.assetScores[1].maturityScore, closeTo(10, 0.001));
      expect(maturity.maturityScore, closeTo(60.56, 0.02));
    },
  );
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
