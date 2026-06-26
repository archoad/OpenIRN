import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/irn_assessment.dart';

class LocalAssessmentRepository {
  const LocalAssessmentRepository();

  static const _schemaVersion = 2;
  static const _keyPrefix = 'openirn.assessment.answers';
  static const _legacyCampaignId = 'default';

  Future<Map<String, CriterionAnswer>> loadCriterionAnswers({
    required String referentialId,
    String? campaignId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    var rawPayload = preferences.getString(
      _storageKey(referentialId, campaignId),
    );

    // Migration douce depuis les patches 009–012 : l'évaluation était stockée
    // uniquement par référentiel, sans identifiant de campagne.
    if ((rawPayload == null || rawPayload.trim().isEmpty) &&
        _canReadLegacyKey(campaignId)) {
      rawPayload = preferences.getString(_legacyStorageKey(referentialId));
    }

    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return <String, CriterionAnswer>{};
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return <String, CriterionAnswer>{};
      }

      final rawAnswers = decoded['answers'];
      if (rawAnswers is! Map) {
        return <String, CriterionAnswer>{};
      }

      final answers = <String, CriterionAnswer>{};
      for (final entry in rawAnswers.entries) {
        final criterionId = entry.key.toString();
        if (criterionId.isEmpty) {
          continue;
        }

        final criterionAnswer = _criterionAnswerFromStoredValue(
          criterionId: criterionId,
          value: entry.value,
        );
        if (criterionAnswer == null) {
          continue;
        }

        final hasUsefulContent =
            criterionAnswer.answer != IrnAnswer.notAnswered ||
                criterionAnswer.justification.trim().isNotEmpty;
        if (hasUsefulContent) {
          answers[criterionId] = criterionAnswer;
        }
      }
      return answers;
    } on FormatException {
      return <String, CriterionAnswer>{};
    }
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
    final preferences = await SharedPreferences.getInstance();
    final serializableAnswers = <String, Map<String, String>>{};

    for (final entry in answers.entries) {
      final criterionAnswer = entry.value;
      final justification = criterionAnswer.justification.trim();
      if (criterionAnswer.answer == IrnAnswer.notAnswered &&
          justification.isEmpty) {
        continue;
      }
      serializableAnswers[entry.key] = <String, String>{
        'answer': criterionAnswer.answer.name,
        if (justification.isNotEmpty) 'justification': justification,
      };
    }

    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'referentialId': referentialId,
      'campaignId': campaignId ?? _legacyCampaignId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'answers': serializableAnswers,
    };

    await preferences.setString(
      _storageKey(referentialId, campaignId),
      jsonEncode(payload),
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey(referentialId, campaignId));
    if (_canReadLegacyKey(campaignId)) {
      await preferences.remove(_legacyStorageKey(referentialId));
    }
  }

  bool _canReadLegacyKey(String? campaignId) {
    return campaignId == null || campaignId.startsWith('local-default-');
  }

  String _legacyStorageKey(String referentialId) {
    return '$_keyPrefix.$referentialId';
  }

  String _storageKey(String referentialId, String? campaignId) {
    final effectiveCampaignId = campaignId ?? _legacyCampaignId;
    return '$_keyPrefix.$referentialId.$effectiveCampaignId';
  }

  CriterionAnswer? _criterionAnswerFromStoredValue({
    required String criterionId,
    required Object? value,
  }) {
    if (value is Map) {
      final answer = _answerFromStoredValue(value['answer']?.toString());
      if (answer == null) {
        return null;
      }
      return CriterionAnswer(
        criterionId: criterionId,
        answer: answer,
        justification: value['justification']?.toString() ?? '',
      );
    }

    final answer = _answerFromStoredValue(value?.toString());
    if (answer == null || answer == IrnAnswer.notAnswered) {
      return null;
    }

    return CriterionAnswer(criterionId: criterionId, answer: answer);
  }

  IrnAnswer? _answerFromStoredValue(String? value) {
    switch (value) {
      case 'resilient':
        return IrnAnswer.resilient;
      case 'nonResilient':
        return IrnAnswer.nonResilient;
      case 'notAnswered':
        return IrnAnswer.notAnswered;
      default:
        return null;
    }
  }
}
