import '../models/app_user.dart';
import '../models/criterion_assignment.dart';
import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_activity_event.dart';
import '../models/local_campaign.dart';

enum SyncPullImportMode { copy, replaceLocal }

class SyncPullImportService {
  const SyncPullImportService();

  SyncPullImportResult importSnapshotPayload({
    required Map<String, dynamic> payload,
    required IrnReferential referential,
    required String serverSyncId,
    required String sourceDeviceId,
    DateTime? importedAt,
    SyncPullImportMode mode = SyncPullImportMode.copy,
  }) {
    final importedAtUtc = (importedAt ?? DateTime.now()).toUtc();
    final warnings = <String>[];

    final type = _asString(payload['type']);
    if (type != 'openirn.syncPush') {
      throw SyncPullImportException(
        type.isEmpty
            ? 'Les données serveur ne sont pas dans un format OpenIRN valide.'
            : 'Format de données serveur non pris en charge : $type.',
      );
    }

    final schemaVersion = _asInt(payload['schemaVersion']);
    if (schemaVersion == null || schemaVersion < 1) {
      throw const SyncPullImportException(
        'Les données serveur ne contiennent pas de version de format valide.',
      );
    }

    final referentialPayload = _asMap(payload['referential']);
    final exportedReferentialId = _asString(referentialPayload['id']);
    if (exportedReferentialId.isNotEmpty &&
        exportedReferentialId != referential.id) {
      throw SyncPullImportException(
        'Les données serveur concernent le référentiel $exportedReferentialId, alors que le référentiel chargé est ${referential.id}.',
      );
    }

    final exportedChecksum = _asString(referentialPayload['checksumSha256']);
    final currentChecksum = referential.checksumSha256 ?? '';
    if (exportedChecksum.isNotEmpty &&
        currentChecksum.isNotEmpty &&
        exportedChecksum != currentChecksum) {
      throw const SyncPullImportException(
        'Le checksum du référentiel distant ne correspond pas au référentiel actuellement chargé.',
      );
    }

    final users = _parseUsers(payload['users'], warnings);
    final userIds = <String>{for (final user in users) user.id};
    final activeCriterionIds = <String>{
      for (final criterion in referential.criteria)
        if (criterion.active) criterion.id,
    };

    final rawCampaigns = payload['campaigns'];
    if (rawCampaigns is! List) {
      throw const SyncPullImportException(
        'Les données serveur ne contiennent pas de liste de campagnes valide.',
      );
    }

    final importedCampaigns = <ImportedRemoteCampaign>[];
    var index = 0;
    for (final rawCampaign in rawCampaigns) {
      index += 1;
      if (rawCampaign is! Map) {
        warnings.add(
          'Une campagne distante a été ignorée car son format est invalide.',
        );
        continue;
      }
      final campaignItem = _asMap(rawCampaign);
      final campaignPayload = _asMap(campaignItem['campaign']);
      if (campaignPayload.isEmpty) {
        warnings.add(
          'Une campagne distante a été ignorée car son bloc campaign est absent.',
        );
        continue;
      }

      final sourceCampaign = LocalCampaign.fromJson(campaignPayload);
      if (sourceCampaign.id.trim().isEmpty) {
        warnings.add('Une campagne distante sans identifiant a été ignorée.');
        continue;
      }
      if (sourceCampaign.referentialId.isNotEmpty &&
          sourceCampaign.referentialId != referential.id) {
        warnings.add(
          'La campagne distante ${sourceCampaign.id} ne correspond pas au référentiel actif et a été ignorée.',
        );
        continue;
      }

      final importedCampaign = _buildImportedCampaign(
        sourceCampaign: sourceCampaign,
        referential: referential,
        serverSyncId: serverSyncId,
        sourceDeviceId: sourceDeviceId,
        importedAt: importedAtUtc,
        index: index,
        mode: mode,
      );
      final criterionAnswers = _parseAnswers(
        rawAnswers: campaignItem['answers'],
        activeCriterionIds: activeCriterionIds,
        warnings: warnings,
      );
      final assignments = _parseAssignments(
        rawAssignments: campaignItem['assignments'],
        referential: referential,
        campaignId: importedCampaign.id,
        activeCriterionIds: activeCriterionIds,
        userIds: userIds,
        importedAt: importedAtUtc,
        warnings: warnings,
      );
      final activityEvents = _parseActivityEvents(
        rawActivityLog: campaignItem['activityLog'],
        referential: referential,
        campaignId: importedCampaign.id,
        serverSyncId: serverSyncId,
        sourceDeviceId: sourceDeviceId,
        importedAt: importedAtUtc,
        warnings: warnings,
      );

      importedCampaigns.add(
        ImportedRemoteCampaign(
          campaign: importedCampaign,
          criterionAnswers: criterionAnswers,
          assignments: assignments,
          activityEvents: activityEvents,
        ),
      );
    }

    if (importedCampaigns.isEmpty && mode != SyncPullImportMode.replaceLocal) {
      throw const SyncPullImportException(
        'Aucune campagne exploitable trouvée dans les données serveur.',
      );
    }

    return SyncPullImportResult(
      serverSyncId: serverSyncId,
      sourceDeviceId: sourceDeviceId,
      users: users,
      campaigns: importedCampaigns,
      warnings: List.unmodifiable(warnings),
    );
  }

  List<AppUser> _parseUsers(Object? rawUsers, List<String> warnings) {
    if (rawUsers == null) {
      warnings.add(
        'Les données serveur ne contiennent pas de liste d’utilisateurs. Les affectations peuvent être incomplètes.',
      );
      return const <AppUser>[];
    }
    if (rawUsers is! List) {
      warnings.add('La liste des utilisateurs reçue du serveur est invalide.');
      return const <AppUser>[];
    }

    final usersById = <String, AppUser>{};
    for (final rawUser in rawUsers) {
      if (rawUser is! Map) {
        warnings.add(
          'Un utilisateur distant a été ignoré car son format est invalide.',
        );
        continue;
      }
      final user = AppUser.fromJson(_asMap(rawUser));
      if (user.id.trim().isEmpty) {
        warnings.add('Un utilisateur distant sans identifiant a été ignoré.');
        continue;
      }
      usersById[user.id] = user;
    }
    return usersById.values.toList(growable: false);
  }

  LocalCampaign _buildImportedCampaign({
    required LocalCampaign sourceCampaign,
    required IrnReferential referential,
    required String serverSyncId,
    required String sourceDeviceId,
    required DateTime importedAt,
    required int index,
    required SyncPullImportMode mode,
  }) {
    if (mode == SyncPullImportMode.replaceLocal) {
      return sourceCampaign.copyWith(updatedAt: importedAt);
    }
    final safeReferentialId = _safeIdPart(referential.id);
    final safeSyncId = _safeIdPart(
      serverSyncId.isEmpty ? 'remote' : serverSyncId,
    );
    final safeCampaignId = _safeIdPart(sourceCampaign.id);
    final safeTimestamp = importedAt.toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final shortSyncId = serverSyncId.length > 12
        ? serverSyncId.substring(0, 12)
        : serverSyncId;
    final importDescription =
        'Importée depuis les données serveur ${serverSyncId.isEmpty ? 'inconnues' : serverSyncId}'
        '${sourceDeviceId.isEmpty ? '' : ' émis par $sourceDeviceId'}.';

    return LocalCampaign(
      id: 'remote-import-$safeReferentialId-$safeSyncId-$safeCampaignId-$safeTimestamp-$index',
      referentialId: referential.id,
      name:
          '${sourceCampaign.name} — serveur ${shortSyncId.isEmpty ? safeTimestamp : shortSyncId}',
      description: sourceCampaign.description.trim().isEmpty
          ? importDescription
          : '${sourceCampaign.description.trim()}\n\n$importDescription',
      information: sourceCampaign.information,
      status: sourceCampaign.status,
      createdAt: importedAt,
      updatedAt: importedAt,
      statusUpdatedAt: importedAt,
    );
  }

  Map<String, CriterionAnswer> _parseAnswers({
    required Object? rawAnswers,
    required Set<String> activeCriterionIds,
    required List<String> warnings,
  }) {
    if (rawAnswers == null) {
      return <String, CriterionAnswer>{};
    }
    if (rawAnswers is! List) {
      warnings.add('Une liste answers distante est invalide et a été ignorée.');
      return <String, CriterionAnswer>{};
    }

    final answers = <String, CriterionAnswer>{};
    for (final rawAnswer in rawAnswers) {
      if (rawAnswer is! Map) {
        warnings.add(
          'Une réponse distante a été ignorée car son format est invalide.',
        );
        continue;
      }
      final answerPayload = _asMap(rawAnswer);
      final criterionId = _asString(answerPayload['criterionId']);
      if (criterionId.isEmpty) {
        warnings.add('Une réponse distante sans criterionId a été ignorée.');
        continue;
      }
      if (!activeCriterionIds.contains(criterionId)) {
        warnings.add(
          'La réponse distante pour $criterionId a été ignorée car le critère n’existe pas dans le référentiel actif.',
        );
        continue;
      }

      final answer = _answerFromValue(answerPayload['answer']);
      var justification = _asString(answerPayload['justification']);
      if (answer == IrnAnswer.notAnswered && justification.isNotEmpty) {
        warnings.add(
          'La justification distante du critère $criterionId a été ignorée car la réponse est N.C.',
        );
        justification = '';
      }
      if (answer == IrnAnswer.notAnswered && justification.isEmpty) {
        continue;
      }
      answers[criterionId] = CriterionAnswer(
        criterionId: criterionId,
        answer: answer,
        justification: justification,
      );
    }
    return answers;
  }

  List<CriterionAssignment> _parseAssignments({
    required Object? rawAssignments,
    required IrnReferential referential,
    required String campaignId,
    required Set<String> activeCriterionIds,
    required Set<String> userIds,
    required DateTime importedAt,
    required List<String> warnings,
  }) {
    if (rawAssignments == null) {
      return const <CriterionAssignment>[];
    }
    if (rawAssignments is! List) {
      warnings.add(
        'Une liste assignments distante est invalide et a été ignorée.',
      );
      return const <CriterionAssignment>[];
    }

    final assignments = <CriterionAssignment>[];
    for (final rawAssignment in rawAssignments) {
      if (rawAssignment is! Map) {
        warnings.add(
          'Une affectation distante a été ignorée car son format est invalide.',
        );
        continue;
      }
      final payload = _asMap(rawAssignment);
      final criterionId = _asString(payload['criterionId']);
      final userId = _asString(payload['userId']);
      if (criterionId.isEmpty || userId.isEmpty) {
        warnings.add('Une affectation distante incomplète a été ignorée.');
        continue;
      }
      if (!activeCriterionIds.contains(criterionId)) {
        warnings.add(
          'L’affectation distante du critère $criterionId a été ignorée car le critère est inconnu.',
        );
        continue;
      }
      if (!userIds.contains(userId)) {
        warnings.add(
          'L’affectation distante du critère $criterionId vers $userId a été ignorée car l’utilisateur est absent des données serveur.',
        );
        continue;
      }
      assignments.add(
        CriterionAssignment.create(
          referentialId: referential.id,
          campaignId: campaignId,
          criterionId: criterionId,
          userId: userId,
          assignedByUserId: _asString(payload['assignedByUserId']),
          now: importedAt,
        ),
      );
    }
    return assignments;
  }

  List<LocalActivityEvent> _parseActivityEvents({
    required Object? rawActivityLog,
    required IrnReferential referential,
    required String campaignId,
    required String serverSyncId,
    required String sourceDeviceId,
    required DateTime importedAt,
    required List<String> warnings,
  }) {
    final events = <LocalActivityEvent>[
      LocalActivityEvent.create(
        referentialId: referential.id,
        campaignId: campaignId,
        type: LocalActivityType.campaignCreated,
        title: 'Campagne importée depuis le serveur',
        description:
            'Données serveur $serverSyncId${sourceDeviceId.isEmpty ? '' : ' depuis $sourceDeviceId'}.',
        now: importedAt,
      ),
    ];

    final activityLog = _asMap(rawActivityLog);
    final rawEvents = activityLog['events'];
    if (rawEvents == null) {
      return events;
    }
    if (rawEvents is! List) {
      warnings.add(
        'Le journal d’activité distant a été ignoré car son format est invalide.',
      );
      return events;
    }

    var index = 0;
    for (final rawEvent in rawEvents) {
      index += 1;
      if (rawEvent is! Map) {
        warnings.add(
          'Un évènement distant a été ignoré car son format est invalide.',
        );
        continue;
      }
      final sourceEvent = LocalActivityEvent.fromJson(_asMap(rawEvent));
      final createdAt = sourceEvent.createdAt;
      final safeTimestamp = createdAt.toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      events.add(
        LocalActivityEvent(
          id: 'activity-remote-$safeTimestamp-${index.toString().padLeft(3, '0')}',
          referentialId: referential.id,
          campaignId: campaignId,
          type: sourceEvent.type,
          title: sourceEvent.title,
          description: sourceEvent.description,
          criterionId: sourceEvent.criterionId,
          fromValue: sourceEvent.fromValue,
          toValue: sourceEvent.toValue,
          createdAt: createdAt,
        ),
      );
    }
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events.take(300).toList(growable: false);
  }

  IrnAnswer _answerFromValue(Object? value) {
    final raw =
        value?.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '_',
        ) ??
        '';
    switch (raw) {
      case 'r':
      case 'resilient':
      case 'resilient_':
      case 'résilient':
        return IrnAnswer.resilient;
      case 'nr':
      case 'non_resilient':
      case 'non_resilient_':
      case 'non_résilient':
        return IrnAnswer.nonResilient;
      case 'nonresilient':
        return IrnAnswer.nonResilient;
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

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String _safeIdPart(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    final trimmed = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }
}

class SyncPullImportResult {
  final String serverSyncId;
  final String sourceDeviceId;
  final List<AppUser> users;
  final List<ImportedRemoteCampaign> campaigns;
  final List<String> warnings;

  const SyncPullImportResult({
    required this.serverSyncId,
    required this.sourceDeviceId,
    required this.users,
    required this.campaigns,
    required this.warnings,
  });

  int get campaignCount => campaigns.length;
  int get answerCount => campaigns.fold<int>(
    0,
    (total, campaign) => total + campaign.criterionAnswers.length,
  );
  int get assignmentCount => campaigns.fold<int>(
    0,
    (total, campaign) => total + campaign.assignments.length,
  );
  int get activityEventCount => campaigns.fold<int>(
    0,
    (total, campaign) => total + campaign.activityEvents.length,
  );
}

class ImportedRemoteCampaign {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final List<CriterionAssignment> assignments;
  final List<LocalActivityEvent> activityEvents;

  const ImportedRemoteCampaign({
    required this.campaign,
    required this.criterionAnswers,
    required this.assignments,
    required this.activityEvents,
  });
}

class SyncPullImportException implements Exception {
  final String message;

  const SyncPullImportException(this.message);

  @override
  String toString() => message;
}
