import '../../domain/models/irn_assessment.dart';
import 'server_campaign_store.dart';

class LocalAssessmentRepository {
  final ServerCampaignStore _store;

  const LocalAssessmentRepository({ServerCampaignStore? store})
    : _store = store ?? const ServerCampaignStore();

  Future<Map<String, CriterionAnswer>> loadCriterionAnswers({
    required String referentialId,
    String? campaignId,
  }) async {
    final resolvedCampaignId = campaignId?.trim() ?? '';
    if (resolvedCampaignId.isEmpty) {
      return <String, CriterionAnswer>{};
    }
    final bundle = await _store.loadBundle(
      referentialId: referentialId,
      campaignId: resolvedCampaignId,
    );
    return Map<String, CriterionAnswer>.from(
      bundle?.criterionAnswers ?? const <String, CriterionAnswer>{},
    );
  }

  Future<Map<String, IrnAnswer>> loadAnswers({
    required String referentialId,
    String? campaignId,
  }) async {
    final criterionAnswers = await loadCriterionAnswers(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    return <String, IrnAnswer>{
      for (final entry in criterionAnswers.entries)
        entry.key: entry.value.answer,
    };
  }

  Future<void> saveCriterionAnswers({
    required String referentialId,
    required Map<String, CriterionAnswer> answers,
    String? campaignId,
  }) async {
    final resolvedCampaignId = campaignId?.trim() ?? '';
    if (resolvedCampaignId.isEmpty) {
      throw const ServerCampaignStoreException(
        'Impossible d’enregistrer une réponse sans campagne serveur.',
      );
    }

    final cleanedAnswers = <String, CriterionAnswer>{};
    for (final entry in answers.entries) {
      final answer = entry.value;
      if (answer.answer == IrnAnswer.notAnswered &&
          answer.justification.trim().isEmpty) {
        continue;
      }
      cleanedAnswers[entry.key] = answer;
    }

    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: resolvedCampaignId,
      update: (bundle) => bundle.copyWith(criterionAnswers: cleanedAnswers),
    );
  }

  Future<void> saveAnswers({
    required String referentialId,
    required Map<String, IrnAnswer> answers,
    String? campaignId,
  }) async {
    await saveCriterionAnswers(
      referentialId: referentialId,
      campaignId: campaignId,
      answers: <String, CriterionAnswer>{
        for (final entry in answers.entries)
          entry.key: CriterionAnswer(
            criterionId: entry.key,
            answer: entry.value,
          ),
      },
    );
  }

  Future<void> clearAnswers({
    required String referentialId,
    String? campaignId,
  }) async {
    final resolvedCampaignId = campaignId?.trim() ?? '';
    if (resolvedCampaignId.isEmpty) {
      return;
    }
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: resolvedCampaignId,
      update: (bundle) =>
          bundle.copyWith(criterionAnswers: const <String, CriterionAnswer>{}),
    );
  }
}
