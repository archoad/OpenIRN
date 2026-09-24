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

  /// Saves [answers], the caller's complete in-memory view of the campaign's
  /// answers, merged onto whatever is freshest on the server rather than
  /// overwriting it outright.
  ///
  /// [baseAnswers] must be the last server snapshot this caller loaded
  /// *before* making its own local edits. Criteria unchanged between
  /// [baseAnswers] and [answers] are left untouched in the freshly-read
  /// server bundle, so a concurrent save by another evaluator (e.g. one
  /// working on different assigned criteria of the same campaign) is not
  /// silently discarded. Only criteria that actually differ from
  /// [baseAnswers] — i.e. this caller's own edits, including clearing an
  /// answer back to not-answered — are applied.
  ///
  /// Returns the cleaned local snapshot that was committed. The caller must
  /// use it as the base for its next save so later removals remain detectable.
  Future<Map<String, CriterionAnswer>> saveCriterionAnswers({
    required String referentialId,
    required Map<String, CriterionAnswer> answers,
    required Map<String, CriterionAnswer> baseAnswers,
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
      update: (bundle) {
        final merged = Map<String, CriterionAnswer>.of(bundle.criterionAnswers);
        final editedKeys = <String>{
          ...baseAnswers.keys,
          ...cleanedAnswers.keys,
        };
        for (final key in editedKeys) {
          if (_sameAnswer(baseAnswers[key], cleanedAnswers[key])) {
            continue;
          }
          final localValue = cleanedAnswers[key];
          if (localValue == null) {
            merged.remove(key);
          } else {
            merged[key] = localValue;
          }
        }
        return bundle.copyWith(
          criterionAnswers: merged,
          replaceAssetAnswers: true,
        );
      },
    );
    return Map<String, CriterionAnswer>.unmodifiable(cleanedAnswers);
  }

  bool _sameAnswer(CriterionAnswer? a, CriterionAnswer? b) {
    if (a == null || b == null) {
      return a == b;
    }
    return a.answer == b.answer && a.justification == b.justification;
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
      update: (bundle) => bundle.copyWith(
        criterionAnswers: const <String, CriterionAnswer>{},
        replaceAssetAnswers: true,
      ),
    );
  }
}
