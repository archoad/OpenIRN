import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_assessment_repository.dart';
import 'package:openirn/data/repositories/server_campaign_store.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/local_campaign.dart';

void main() {
  group('LocalAssessmentRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalAssessmentRepository();
      expect(repository, isA<LocalAssessmentRepository>());
    });

    test(
      'removes an answer created then cleared in the same session',
      () async {
        final store = _InMemoryServerCampaignStore();
        final repository = LocalAssessmentRepository(store: store);

        final savedAnswers = await repository.saveCriterionAnswers(
          referentialId: 'referential-1',
          campaignId: 'campaign-1',
          answers: const <String, CriterionAnswer>{
            'criterion-1': CriterionAnswer(
              criterionId: 'criterion-1',
              answer: IrnAnswer.result,
            ),
          },
          baseAnswers: const <String, CriterionAnswer>{},
        );

        expect(
          store.bundle.criterionAnswers['criterion-1']?.answer,
          IrnAnswer.result,
        );

        final clearedAnswers = await repository.saveCriterionAnswers(
          referentialId: 'referential-1',
          campaignId: 'campaign-1',
          answers: const <String, CriterionAnswer>{},
          baseAnswers: savedAnswers,
        );

        expect(clearedAnswers, isEmpty);
        expect(store.bundle.criterionAnswers, isEmpty);
      },
    );

    test('preserves a concurrent answer on another criterion', () async {
      final store = _InMemoryServerCampaignStore(
        criterionAnswers: const <String, CriterionAnswer>{
          'criterion-1': CriterionAnswer(
            criterionId: 'criterion-1',
            answer: IrnAnswer.nonResilient,
          ),
          'criterion-2': CriterionAnswer(
            criterionId: 'criterion-2',
            answer: IrnAnswer.medium,
          ),
        },
      );
      final repository = LocalAssessmentRepository(store: store);

      await repository.saveCriterionAnswers(
        referentialId: 'referential-1',
        campaignId: 'campaign-1',
        answers: const <String, CriterionAnswer>{
          'criterion-1': CriterionAnswer(
            criterionId: 'criterion-1',
            answer: IrnAnswer.result,
          ),
        },
        baseAnswers: const <String, CriterionAnswer>{
          'criterion-1': CriterionAnswer(
            criterionId: 'criterion-1',
            answer: IrnAnswer.nonResilient,
          ),
        },
      );

      expect(
        store.bundle.criterionAnswers['criterion-1']?.answer,
        IrnAnswer.result,
      );
      expect(
        store.bundle.criterionAnswers['criterion-2']?.answer,
        IrnAnswer.medium,
      );
    });
  });
}

class _InMemoryServerCampaignStore extends ServerCampaignStore {
  ServerCampaignBundle bundle;

  _InMemoryServerCampaignStore({
    Map<String, CriterionAnswer> criterionAnswers =
        const <String, CriterionAnswer>{},
  }) : bundle = ServerCampaignBundle(
         campaign: LocalCampaign(
           id: 'campaign-1',
           referentialId: 'referential-1',
           name: 'Campaign 1',
           createdAt: DateTime.utc(2026),
           updatedAt: DateTime.utc(2026),
           statusUpdatedAt: DateTime.utc(2026),
         ),
         criterionAnswers: criterionAnswers,
       );

  @override
  Future<void> updateBundle({
    required String referentialId,
    required String campaignId,
    required ServerCampaignBundle Function(ServerCampaignBundle bundle) update,
  }) async {
    expect(referentialId, 'referential-1');
    expect(campaignId, 'campaign-1');
    bundle = update(bundle);
  }
}
