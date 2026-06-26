import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/models/sync_configuration.dart';
import 'package:openirn/domain/services/sync_push_payload_service.dart';

void main() {
  group('SyncPushPayloadService', () {
    test('builds a local sync push payload', () {
      const service = SyncPushPayloadService();
      final generatedAt = DateTime.utc(2026, 6, 24, 12);
      final userTimestamp = DateTime.utc(2026, 6, 24, 10);
      final campaignTimestamp = DateTime.utc(2026, 6, 24, 11);
      final user = AppUser(
        id: 'user-1',
        firstName: 'Alice',
        lastName: 'Martin',
        email: 'alice@example.test',
        role: AppUserRole.evaluator,
        active: true,
        createdAt: userTimestamp,
        updatedAt: userTimestamp,
      );
      final campaign = LocalCampaign(
        id: 'campaign-1',
        referentialId: 'adri-irn-v1.1',
        name: 'Campagne test',
        createdAt: campaignTimestamp,
        updatedAt: campaignTimestamp,
        statusUpdatedAt: campaignTimestamp,
      );

      final payload = service.buildPushPayload(
        generatedAt: generatedAt,
        referential: const IrnReferential(
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
          criteria: <IrnCriterion>[],
        ),
        configuration: SyncConfiguration.empty(deviceId: 'device-1').copyWith(
          enabled: true,
          apiBaseUrl: 'https://openirn.example/api',
          tenantId: 'tenant-1',
          apiToken: 'test-token-with-more-than-16-chars',
        ),
        activeUser: user,
        users: <AppUser>[user],
        campaigns: <CampaignSyncSnapshot>[
          CampaignSyncSnapshot(
            campaign: campaign,
            criterionAnswers: const <String, CriterionAnswer>{
              'RES-1.1': CriterionAnswer(
                criterionId: 'RES-1.1',
                answer: IrnAnswer.resilient,
                justification: 'Justifié.',
              ),
            },
            assignments: const [],
            activityEvents: const [],
          ),
        ],
      );

      expect(payload['type'], 'openirn.syncPush');
      expect((payload['sync'] as Map<String, dynamic>)['isConfigured'], isTrue);
      expect(
        (payload['sync'] as Map<String, dynamic>).containsKey('apiToken'),
        isFalse,
      );
      expect((payload['summary'] as Map<String, dynamic>)['campaignCount'], 1);
      expect((payload['summary'] as Map<String, dynamic>)['answerCount'], 1);
      expect(
        ((payload['campaigns'] as List).first
            as Map<String, dynamic>)['localSummary'],
        isA<Map<String, dynamic>>(),
      );
    });
  });
}
