import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_activity_event.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/services/assessment_export_service.dart';

void main() {
  test(
    'buildPayload exports referential metadata, answers, justifications and scoring',
    () {
      const referential = IrnReferential(
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

      final payload = const AssessmentExportService().buildPayload(
        referential: referential,
        campaign:
            LocalCampaign.defaultForReferential(
              referentialId: referential.id,
              referentialVersion: referential.version,
              now: DateTime.utc(2026, 6, 22),
            ).copyWith(
              status: LocalCampaignStatus.readyForReview,
              information: const CampaignInformation(
                systemName: 'SI Facturation',
                systemDescription: 'Système critique de facturation.',
                projectDirectorFirstName: 'Alice',
                projectDirectorLastName: 'Martin',
                projectDirectorEmail: 'alice.martin@example.test',
              ),
            ),
        criterionAnswers: const <String, CriterionAnswer>{
          'RES-1.1': CriterionAnswer(
            criterionId: 'RES-1.1',
            answer: IrnAnswer.resilient,
            justification: 'Gouvernance documentée.',
          ),
          'RES-2.1': CriterionAnswer(
            criterionId: 'RES-2.1',
            answer: IrnAnswer.nonResilient,
          ),
        },
        activityEvents: <LocalActivityEvent>[
          LocalActivityEvent(
            id: 'activity-001',
            referentialId: 'adri-irn-vtest',
            campaignId: 'local-campaign-default-adri-irn-vtest',
            type: LocalActivityType.answerChanged,
            title: 'Réponse modifiée',
            description: 'RES-1.1 : N.C. → R',
            criterionId: 'RES-1.1',
            fromValue: 'NC',
            toValue: 'R',
            createdAt: DateTime.utc(2026, 6, 22, 10),
          ),
        ],
        exportedAt: DateTime.utc(2026, 6, 22, 12),
      );

      expect(payload['schemaVersion'], 6);
      expect(payload['collaboration'], isA<Map<String, dynamic>>());
      expect(payload['type'], 'openirn.localAssessmentExport');
      expect(
        (payload['referential'] as Map<String, dynamic>)['checksumSha256'],
        'abc123',
      );

      final campaign = payload['campaign'] as Map<String, dynamic>;
      expect(campaign['status'], 'ready_for_review');
      expect(campaign['statusLabel'], 'Prêt pour revue');
      final system = campaign['system'] as Map<String, dynamic>;
      expect(system['name'], 'SI Facturation');
      final projectDirector =
          campaign['projectDirector'] as Map<String, dynamic>;
      expect(projectDirector['email'], 'alice.martin@example.test');

      final scoring = payload['scoring'] as Map<String, dynamic>;
      final global = scoring['global'] as Map<String, dynamic>;
      expect(global['officialScore'], 50.0);
      expect(global['completionRate'], 1.0);

      final activityLog = payload['activityLog'] as Map<String, dynamic>;
      expect(activityLog['included'], isTrue);
      expect(activityLog['eventCount'], 1);
      final events = activityLog['events'] as List<dynamic>;
      expect(events, hasLength(1));
      expect((events.first as Map<String, dynamic>)['type'], 'answer_changed');
      expect((events.first as Map<String, dynamic>)['criterionId'], 'RES-1.1');

      final answers = payload['answers'] as List<dynamic>;
      expect(answers, hasLength(2));

      final firstAnswer = answers.first as Map<String, dynamic>;
      expect(firstAnswer['answer'], 'R');
      expect(firstAnswer['justification'], 'Gouvernance documentée.');
      expect(firstAnswer['hasJustification'], isTrue);
    },
  );

  test('buildPrettyJson returns valid formatted json', () {
    const referential = IrnReferential(
      id: 'adri-irn-empty',
      version: 'vempty',
      source: IrnSource(
        type: 'gitlab',
        url: '',
        projectPath: '',
        defaultBranch: 'main',
        filePath: '',
        license: 'CC BY-NC-ND 4.0',
      ),
      pillars: [],
      criteria: [],
    );

    final payload = const AssessmentExportService().buildPrettyJson(
      referential: referential,
      criterionAnswers: const <String, CriterionAnswer>{},
      exportedAt: DateTime.utc(2026),
    );

    expect(jsonDecode(payload), isA<Map<String, dynamic>>());
    expect(payload.contains('\n  "schemaVersion"'), isTrue);
  });
}
