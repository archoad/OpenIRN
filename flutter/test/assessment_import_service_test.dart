import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/services/assessment_import_service.dart';

void main() {
  group('AssessmentImportService', () {
    test('imports a local OpenIRN export into a new local campaign', () {
      final referential = _referential();
      final result = const AssessmentImportService().importFromJson(
        rawJson: '''
{
  "schemaVersion": 4,
  "type": "openirn.localAssessmentExport",
  "application": "OpenIRN",
  "campaign": {
    "id": "local-source",
    "name": "Campagne source",
    "description": "Description source",
    "system": {
      "name": "SI Paiement",
      "description": "Système de paiement critique."
    },
    "projectDirector": {
      "firstName": "Bruno",
      "lastName": "Durand",
      "email": "bruno.durand@example.test"
    },
    "status": "ready_for_review",
    "createdAt": "2026-06-22T08:00:00.000Z",
    "updatedAt": "2026-06-22T09:00:00.000Z",
    "statusUpdatedAt": "2026-06-22T09:00:00.000Z"
  },
  "referential": {
    "id": "adri-irn-vtest",
    "version": "vtest",
    "checksumSha256": "abc123"
  },
  "answers": [
    {
      "criterionId": "RES-1.1",
      "answer": "R",
      "justification": "Gouvernance documentée."
    },
    {
      "criterionId": "RES-2.1",
      "answer": "NR",
      "justification": "Plan de remédiation à formaliser."
    },
    {
      "criterionId": "RES-9.9",
      "answer": "R",
      "justification": "Critère inconnu."
    }
  ],
  "activityLog": {
    "included": true,
    "eventCount": 1,
    "events": [
      {
        "id": "activity-source",
        "type": "answer_changed",
        "title": "Réponse modifiée",
        "description": "RES-1.1",
        "criterionId": "RES-1.1",
        "fromValue": "N.C.",
        "toValue": "R",
        "createdAt": "2026-06-22T10:00:00.000Z"
      }
    ]
  }
}
''',
        referential: referential,
        importedAt: DateTime.utc(2026, 6, 23, 12),
      );

      expect(result.campaign.referentialId, referential.id);
      expect(result.campaign.name, contains('Campagne source'));
      expect(result.campaign.status, LocalCampaignStatus.readyForReview);
      expect(result.campaign.information.systemName, 'SI Paiement');
      expect(
        result.campaign.information.projectDirectorFullName,
        'Bruno Durand',
      );
      expect(
        result.campaign.information.projectDirectorEmail,
        'bruno.durand@example.test',
      );
      expect(result.criterionAnswers, hasLength(2));
      expect(result.criterionAnswers['RES-1.1']!.answer, IrnAnswer.resilient);
      expect(
        result.criterionAnswers['RES-1.1']!.justification,
        'Gouvernance documentée.',
      );
      expect(
        result.criterionAnswers['RES-2.1']!.answer,
        IrnAnswer.nonResilient,
      );
      expect(result.activityEvents.length, 2);
      expect(
        result.activityEvents.every(
          (event) => event.campaignId == result.campaign.id,
        ),
        isTrue,
      );
      expect(result.warnings.single, contains('RES-9.9'));
    });

    test('rejects a JSON export targeting another referential', () {
      final referential = _referential();

      expect(
        () => const AssessmentImportService().importFromJson(
          rawJson: '''
{
  "schemaVersion": 4,
  "type": "openirn.localAssessmentExport",
  "referential": {"id": "another-referential"},
  "answers": []
}
''',
          referential: referential,
        ),
        throwsA(isA<AssessmentImportException>()),
      );
    });
  });
}

IrnReferential _referential() {
  return const IrnReferential(
    id: 'adri-irn-vtest',
    version: 'vtest',
    source: IrnSource(
      type: 'gitlab',
      url: 'https://example.test/adri-irn',
      projectPath: 'digitalresilienceinitiative/adri-irn',
      defaultBranch: 'main',
      filePath: 'Questionnaire.xlsx',
      license: 'CC BY-NC-ND 4.0',
      checksumSha256: 'abc123',
    ),
    pillars: [
      IrnPillar(id: 'RES-1', code: 'RES-1', label: 'Pilier 1'),
      IrnPillar(id: 'RES-2', code: 'RES-2', label: 'Pilier 2'),
    ],
    criteria: [
      IrnCriterion(
        id: 'RES-1.1',
        code: 'RES-1.1',
        sourceCode: 'RES-1.1',
        pillarId: 'RES-1',
        label: 'Critère 1',
        shortLabel: 'C1',
        description: '',
        scope: CriterionScope.organization,
        sourceScope: 'Organisation',
        answerMode: 'R_NR',
        regulatoryReferences: '',
        recommendations: '',
        active: true,
        source: CriterionSourceLocation(sheet: 'Référentiel v1', row: 1),
      ),
      IrnCriterion(
        id: 'RES-2.1',
        code: 'RES-2.1',
        sourceCode: 'RES-2.1',
        pillarId: 'RES-2',
        label: 'Critère 2',
        shortLabel: 'C2',
        description: '',
        scope: CriterionScope.asset,
        sourceScope: 'Actif numérique',
        answerMode: 'R_NR',
        regulatoryReferences: '',
        recommendations: '',
        active: true,
        source: CriterionSourceLocation(sheet: 'Référentiel v1', row: 2),
      ),
    ],
  );
}
