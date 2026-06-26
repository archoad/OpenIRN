import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/services/sync_pull_import_service.dart';

void main() {
  const referential = IrnReferential(
    id: 'adri-irn-v1.1',
    version: 'v1.1',
    source: IrnSource(
      type: 'gitlab',
      url: 'https://gitlab.com/digitalresilienceinitiative/adri-irn',
      projectPath: 'digitalresilienceinitiative/adri-irn',
      defaultBranch: 'main',
      filePath: 'Questionnaire_IRN_v.1.1.xlsx',
      license: 'CC BY-NC-ND 4.0',
      checksumSha256: 'abc',
    ),
    pillars: <IrnPillar>[],
    criteria: <IrnCriterion>[
      IrnCriterion(
        id: 'RES-1.1',
        code: 'RES-1.1',
        sourceCode: 'RES-1.1',
        pillarId: 'RES-1',
        label: 'Critère de test',
        shortLabel: 'Critère de test',
        description: '',
        scope: CriterionScope.organization,
        sourceScope: 'Organisation',
        answerMode: 'R_NR',
        regulatoryReferences: '',
        recommendations: '',
        active: true,
        source: CriterionSourceLocation(sheet: 'test', row: 1),
      ),
    ],
  );

  test('importe un snapshot syncPush en campagne locale copiée', () {
    final result = const SyncPullImportService().importSnapshotPayload(
      referential: referential,
      serverSyncId: 'sync-001',
      sourceDeviceId: 'device-a',
      importedAt: DateTime.utc(2026, 6, 24, 12),
      payload: <String, dynamic>{
        'schemaVersion': 1,
        'type': 'openirn.syncPush',
        'referential': <String, dynamic>{
          'id': 'adri-irn-v1.1',
          'checksumSha256': 'abc',
        },
        'users': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'user-1',
            'firstName': 'Alice',
            'lastName': 'Martin',
            'email': 'alice@example.test',
            'role': 'evaluator',
            'active': true,
            'createdAt': '2026-06-24T10:00:00Z',
            'updatedAt': '2026-06-24T10:00:00Z',
          },
        ],
        'campaigns': <Map<String, dynamic>>[
          <String, dynamic>{
            'campaign': <String, dynamic>{
              'id': 'local-source-campaign',
              'referentialId': 'adri-irn-v1.1',
              'name': 'Campagne source',
              'description': 'Description source',
              'status': 'draft',
              'createdAt': '2026-06-24T10:00:00Z',
              'updatedAt': '2026-06-24T10:00:00Z',
              'statusUpdatedAt': '2026-06-24T10:00:00Z',
            },
            'answers': <Map<String, dynamic>>[
              <String, dynamic>{
                'criterionId': 'RES-1.1',
                'answer': 'resilient',
                'justification': 'Justification distante',
              },
            ],
            'assignments': <Map<String, dynamic>>[
              <String, dynamic>{'criterionId': 'RES-1.1', 'userId': 'user-1'},
            ],
            'activityLog': <String, dynamic>{
              'events': <Map<String, dynamic>>[],
            },
          },
        ],
      },
    );

    expect(result.campaignCount, 1);
    expect(result.users.single.id, 'user-1');
    expect(result.campaigns.single.campaign.id, startsWith('remote-import-'));
    expect(result.campaigns.single.campaign.name, contains('Campagne source'));
    expect(
      result.campaigns.single.criterionAnswers['RES-1.1']?.answer,
      IrnAnswer.resilient,
    );
    expect(
      result.campaigns.single.criterionAnswers['RES-1.1']?.justification,
      'Justification distante',
    );
    expect(result.campaigns.single.assignments.single.userId, 'user-1');
    expect(
      result.campaigns.single.activityEvents.first.title,
      'Campagne importée depuis le serveur',
    );
  });

  test('refuse un snapshot destiné à un autre référentiel', () {
    expect(
      () => const SyncPullImportService().importSnapshotPayload(
        referential: referential,
        serverSyncId: 'sync-002',
        sourceDeviceId: 'device-a',
        payload: <String, dynamic>{
          'schemaVersion': 1,
          'type': 'openirn.syncPush',
          'referential': <String, dynamic>{'id': 'autre-referentiel'},
          'users': <Map<String, dynamic>>[],
          'campaigns': <Map<String, dynamic>>[],
        },
      ),
      throwsA(isA<SyncPullImportException>()),
    );
  });
}
