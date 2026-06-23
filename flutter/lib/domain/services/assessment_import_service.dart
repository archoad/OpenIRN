import 'dart:convert';

import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_activity_event.dart';
import '../models/local_campaign.dart';

class AssessmentImportService {
  const AssessmentImportService();

  AssessmentImportResult importFromJson({
    required String rawJson,
    required IrnReferential referential,
    DateTime? importedAt,
  }) {
    final importedAtUtc = (importedAt ?? DateTime.now()).toUtc();
    final decoded = _decodePayload(rawJson);
    final schemaVersion = _asInt(decoded['schemaVersion']);
    if (schemaVersion == null || schemaVersion < 1) {
      throw const AssessmentImportException(
          'Le JSON ne contient pas de schemaVersion OpenIRN valide.');
    }

    final type = _asString(decoded['type']);
    if (type.isNotEmpty && type != 'openirn.localAssessmentExport') {
      throw AssessmentImportException('Type d’export non supporté : $type.');
    }

    final referentialPayload = _asMap(decoded['referential']);
    final exportedReferentialId = _asString(referentialPayload['id']);
    if (exportedReferentialId.isNotEmpty &&
        exportedReferentialId != referential.id) {
      throw AssessmentImportException(
        'Le JSON cible le référentiel $exportedReferentialId, alors que le référentiel chargé est ${referential.id}.',
      );
    }

    final exportedChecksum = _asString(referentialPayload['checksumSha256']);
    final currentChecksum = referential.checksumSha256 ?? '';
    if (exportedChecksum.isNotEmpty &&
        currentChecksum.isNotEmpty &&
        exportedChecksum != currentChecksum) {
      throw const AssessmentImportException(
        'Le checksum du référentiel ne correspond pas au référentiel actuellement chargé.',
      );
    }

    final warnings = <String>[];
    final campaign = _buildImportedCampaign(
      decoded: decoded,
      referential: referential,
      importedAt: importedAtUtc,
    );
    final criterionAnswers = _parseAnswers(
      decoded: decoded,
      referential: referential,
      warnings: warnings,
    );
    final activityEvents = _parseActivityEvents(
      decoded: decoded,
      referential: referential,
      campaignId: campaign.id,
      importedAt: importedAtUtc,
      warnings: warnings,
    );

    return AssessmentImportResult(
      campaign: campaign,
      criterionAnswers: criterionAnswers,
      activityEvents: activityEvents,
      warnings: List.unmodifiable(warnings),
    );
  }

  Map<String, dynamic> _decodePayload(String rawJson) {
    if (rawJson.trim().isEmpty) {
      throw const AssessmentImportException('Le contenu JSON est vide.');
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        throw const AssessmentImportException(
            'Le JSON doit contenir un objet racine.');
      }
      return decoded;
    } on FormatException catch (error) {
      throw AssessmentImportException('JSON invalide : ${error.message}.');
    }
  }

  LocalCampaign _buildImportedCampaign({
    required Map<String, dynamic> decoded,
    required IrnReferential referential,
    required DateTime importedAt,
  }) {
    final campaignPayload = _asMap(decoded['campaign']);
    final exportedName =
        _asString(campaignPayload['name'], fallback: 'Évaluation IRN');
    final exportedDescription = _asString(campaignPayload['description']);
    final information = _campaignInformationFromPayload(campaignPayload);
    final importedLabel = _formatCompactDate(importedAt);
    final safeTimestamp =
        importedAt.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    final safeReferentialId = _safeIdPart(referential.id);

    return LocalCampaign(
      id: 'local-import-$safeReferentialId-$safeTimestamp',
      referentialId: referential.id,
      name: '$exportedName — import $importedLabel',
      description: exportedDescription.isEmpty
          ? 'Campagne importée depuis un export JSON OpenIRN.'
          : '$exportedDescription\n\nImportée depuis un export JSON OpenIRN.',
      information: information,
      status: LocalCampaignStatus.fromJson(campaignPayload['status']),
      createdAt: importedAt,
      updatedAt: importedAt,
      statusUpdatedAt: importedAt,
    );
  }

  CampaignInformation _campaignInformationFromPayload(
      Map<String, dynamic> campaignPayload) {
    final system = _asMap(campaignPayload['system']);
    final projectDirector = _asMap(campaignPayload['projectDirector']);
    final legacyInformation = _asMap(campaignPayload['information']);

    return CampaignInformation(
      systemName: _firstNonEmpty(<Object?>[
        system['name'],
        legacyInformation['systemName'],
        campaignPayload['systemName'],
      ]),
      systemDescription: _firstNonEmpty(<Object?>[
        system['description'],
        legacyInformation['systemDescription'],
        campaignPayload['systemDescription'],
      ]),
      projectDirectorFirstName: _firstNonEmpty(<Object?>[
        projectDirector['firstName'],
        legacyInformation['projectDirectorFirstName'],
        campaignPayload['projectDirectorFirstName'],
      ]),
      projectDirectorLastName: _firstNonEmpty(<Object?>[
        projectDirector['lastName'],
        legacyInformation['projectDirectorLastName'],
        campaignPayload['projectDirectorLastName'],
      ]),
      projectDirectorEmail: _firstNonEmpty(<Object?>[
        projectDirector['email'],
        legacyInformation['projectDirectorEmail'],
        campaignPayload['projectDirectorEmail'],
      ]),
    );
  }

  Map<String, CriterionAnswer> _parseAnswers({
    required Map<String, dynamic> decoded,
    required IrnReferential referential,
    required List<String> warnings,
  }) {
    final rawAnswers = decoded['answers'];
    if (rawAnswers is! List) {
      throw const AssessmentImportException(
          'Le JSON ne contient pas de liste answers valide.');
    }

    final activeCriterionIds = <String>{
      for (final criterion in referential.criteria)
        if (criterion.active) criterion.id,
    };
    final criterionAnswers = <String, CriterionAnswer>{};

    for (final rawAnswer in rawAnswers) {
      if (rawAnswer is! Map) {
        warnings.add('Une réponse a été ignorée car son format est invalide.');
        continue;
      }
      final answerPayload = _asMap(rawAnswer);
      final criterionId = _asString(answerPayload['criterionId']);
      if (criterionId.isEmpty) {
        warnings.add('Une réponse sans criterionId a été ignorée.');
        continue;
      }
      if (!activeCriterionIds.contains(criterionId)) {
        warnings.add(
            'Le critère $criterionId n’existe pas dans le référentiel actif et a été ignoré.');
        continue;
      }

      final answer = _answerFromExport(answerPayload['answer']);
      var justification = _asString(answerPayload['justification']);
      if (answer == IrnAnswer.notAnswered && justification.isNotEmpty) {
        warnings.add(
            'La justification du critère $criterionId a été ignorée car la réponse est N.C.');
        justification = '';
      }

      if (answer == IrnAnswer.notAnswered && justification.isEmpty) {
        continue;
      }

      criterionAnswers[criterionId] = CriterionAnswer(
        criterionId: criterionId,
        answer: answer,
        justification: justification,
      );
    }

    return criterionAnswers;
  }

  List<LocalActivityEvent> _parseActivityEvents({
    required Map<String, dynamic> decoded,
    required IrnReferential referential,
    required String campaignId,
    required DateTime importedAt,
    required List<String> warnings,
  }) {
    final activityLog = _asMap(decoded['activityLog']);
    final rawEvents = activityLog['events'];
    final events = <LocalActivityEvent>[
      LocalActivityEvent.create(
        referentialId: referential.id,
        campaignId: campaignId,
        type: LocalActivityType.campaignCreated,
        title: 'Campagne importée',
        description: 'Import JSON local depuis un export OpenIRN.',
        now: importedAt,
      ),
    ];

    if (rawEvents == null) {
      return events;
    }
    if (rawEvents is! List) {
      warnings.add(
          'Le journal d’activité exporté a été ignoré car son format est invalide.');
      return events;
    }

    var index = 0;
    for (final rawEvent in rawEvents) {
      index += 1;
      if (rawEvent is! Map) {
        warnings.add(
            'Un évènement du journal a été ignoré car son format est invalide.');
        continue;
      }
      final eventPayload = _asMap(rawEvent);
      final createdAt = _asDate(eventPayload['createdAt']) ?? importedAt;
      final safeTimestamp =
          createdAt.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      final type = LocalActivityType.fromJson(eventPayload['type']);

      events.add(
        LocalActivityEvent(
          id: 'activity-import-$safeTimestamp-${index.toString().padLeft(3, '0')}',
          referentialId: referential.id,
          campaignId: campaignId,
          type: type,
          title: _asString(eventPayload['title'], fallback: type.label),
          description: _asString(eventPayload['description']),
          criterionId: _blankToNull(eventPayload['criterionId']?.toString()),
          fromValue: _blankToNull(eventPayload['fromValue']?.toString()),
          toValue: _blankToNull(eventPayload['toValue']?.toString()),
          createdAt: createdAt,
        ),
      );
    }

    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events.take(300).toList(growable: false);
  }

  IrnAnswer _answerFromExport(Object? value) {
    final raw =
        value?.toString().trim().toUpperCase().replaceAll('.', '') ?? '';
    switch (raw) {
      case 'R':
      case 'RESILIENT':
      case 'RÉSILIENT':
        return IrnAnswer.resilient;
      case 'NR':
      case 'NON_RESILIENT':
      case 'NON-RÉSILIENT':
      case 'NON_RESILIENTE':
        return IrnAnswer.nonResilient;
      case 'NC':
      case 'N/C':
      case 'N C':
      case 'NOT_ANSWERED':
      case 'NON COTÉ':
      default:
        return IrnAnswer.notAnswered;
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _asString(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _asDate(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _safeIdPart(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _formatCompactDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class AssessmentImportResult {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final List<LocalActivityEvent> activityEvents;
  final List<String> warnings;

  const AssessmentImportResult({
    required this.campaign,
    required this.criterionAnswers,
    required this.activityEvents,
    this.warnings = const <String>[],
  });

  int get answeredCount {
    return criterionAnswers.values
        .where((answer) => answer.answer.isCounted)
        .length;
  }

  int get justificationCount {
    return criterionAnswers.values
        .where((answer) => answer.justification.trim().isNotEmpty)
        .length;
  }
}

class AssessmentImportException implements Exception {
  final String message;

  const AssessmentImportException(this.message);

  @override
  String toString() => message;
}
