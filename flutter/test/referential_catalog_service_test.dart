import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/services/referential_catalog_service.dart';

void main() {
  test('criteriaByPillar regroupe les critères par pilier', () {
    const referential = IrnReferential(
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
          label: 'Gouvernance',
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
      ],
    );

    const service = ReferentialCatalogService();
    final result = service.criteriaByPillar(referential);

    expect(result[referential.pillars.first], hasLength(1));
    expect(result[referential.pillars.last], isEmpty);
  });

  test('searchCriteria recherche par code et libellé', () {
    const criterion = IrnCriterion(
      id: 'RES-6.3',
      code: 'RES-6.3',
      sourceCode: 'RES-6.3',
      pillarId: 'RES-6',
      label: 'Ouverture du code et des licences',
      shortLabel: '',
      description: '',
      scope: CriterionScope.asset,
      sourceScope: 'Actif numérique',
      answerMode: 'R_NR',
      regulatoryReferences: '',
      recommendations: '',
      active: true,
      source: CriterionSourceLocation(),
    );
    const referential = IrnReferential(
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
      pillars: [IrnPillar(id: 'RES-6', code: 'RES-6', label: 'Technologique')],
      criteria: [criterion],
    );

    const service = ReferentialCatalogService();

    expect(service.searchCriteria(referential, 'RES-6.3'), hasLength(1));
    expect(service.searchCriteria(referential, 'licences'), hasLength(1));
    expect(service.searchCriteria(referential, 'absent'), isEmpty);
  });
}
