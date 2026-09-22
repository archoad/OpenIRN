import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_campaign_repository.dart';
import 'package:openirn/data/repositories/server_campaign_store.dart';
import 'package:openirn/domain/models/criterion_assignment.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/local_campaign.dart';

class _RecordingServerCampaignStore extends ServerCampaignStore {
  int loadCount = 0;

  @override
  Future<List<ServerCampaignBundle>> loadBundles({
    required String referentialId,
  }) async {
    loadCount += 1;
    final timestamp = DateTime.utc(2026, 9, 22);
    const campaignId = 'campaign-a';
    return <ServerCampaignBundle>[
      ServerCampaignBundle(
        campaign: LocalCampaign(
          id: campaignId,
          referentialId: 'adri-irn-v1.1',
          name: 'Campaign A',
          createdAt: timestamp,
          updatedAt: timestamp,
          statusUpdatedAt: timestamp,
        ),
        criterionAnswers: const <String, CriterionAnswer>{
          'criterion-a': CriterionAnswer(
            criterionId: 'criterion-a',
            answer: IrnAnswer.result,
          ),
        },
        assignments: <CriterionAssignment>[
          CriterionAssignment.create(
            referentialId: referentialId,
            campaignId: campaignId,
            criterionId: 'criterion-a',
            userId: 'user-a',
            now: timestamp,
          ),
        ],
      ),
    ];
  }
}

void main() {
  group('LocalCampaignRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalCampaignRepository();
      expect(repository, isA<LocalCampaignRepository>());
    });

    test(
      'loads campaigns, answers and assignments in one server read',
      () async {
        final store = _RecordingServerCampaignStore();
        final repository = LocalCampaignRepository(store: store);

        final campaignData = await repository.loadCampaignData(
          referentialId: 'adri-irn-v1.1',
        );

        expect(store.loadCount, 1);
        expect(campaignData, hasLength(1));
        expect(campaignData.single.campaign.name, 'Campaign A');
        expect(
          campaignData.single.criterionAnswers['criterion-a']?.answer,
          IrnAnswer.result,
        );
        expect(campaignData.single.assignments.single.userId, 'user-a');
      },
    );
  });
}
