import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/app_session_manager.dart';
import '../api/openirn_api_client.dart';
import 'local_sync_configuration_repository.dart';

class ServerCampaignBundle {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final List<CriterionAssignment> assignments;
  final List<LocalActivityEvent> activityEvents;

  const ServerCampaignBundle({
    required this.campaign,
    this.criterionAnswers = const <String, CriterionAnswer>{},
    this.assignments = const <CriterionAssignment>[],
    this.activityEvents = const <LocalActivityEvent>[],
  });

  ServerCampaignBundle copyWith({
    LocalCampaign? campaign,
    Map<String, CriterionAnswer>? criterionAnswers,
    List<CriterionAssignment>? assignments,
    List<LocalActivityEvent>? activityEvents,
  }) {
    return ServerCampaignBundle(
      campaign: campaign ?? this.campaign,
      criterionAnswers: criterionAnswers ?? this.criterionAnswers,
      assignments: assignments ?? this.assignments,
      activityEvents: activityEvents ?? this.activityEvents,
    );
  }
}

class ServerCampaignStoreException implements Exception {
  final String message;

  const ServerCampaignStoreException(this.message);

  @override
  String toString() => message;
}

class ServerCampaignStore {
  final LocalSyncConfigurationRepository configurationRepository;
  final OpenIrnApiClient apiClient;

  const ServerCampaignStore({
    this.configurationRepository = const LocalSyncConfigurationRepository(),
    this.apiClient = const OpenIrnApiClient(),
  });

  Future<List<ServerCampaignBundle>> loadBundles({
    required String referentialId,
  }) async {
    final configuration = await configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return const <ServerCampaignBundle>[];
    }

    final pull = await apiClient.pullSnapshots(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      limit: 1,
    );

    if (pull.status == OpenIrnApiPullStatus.empty) {
      return const <ServerCampaignBundle>[];
    }
    if (pull.status != OpenIrnApiPullStatus.available ||
        pull.snapshots.isEmpty) {
      throw ServerCampaignStoreException('${pull.title} — ${pull.message}');
    }

    final payload = pull.snapshots.first.payload;
    if (payload == null || payload.isEmpty) {
      return const <ServerCampaignBundle>[];
    }

    final rawCampaigns = payload['campaigns'];
    if (rawCampaigns is! List) {
      return const <ServerCampaignBundle>[];
    }

    final bundles = <ServerCampaignBundle>[];
    for (final rawCampaign in rawCampaigns) {
      if (rawCampaign is! Map) {
        continue;
      }
      final campaignItem = _asMap(rawCampaign);
      final campaignPayload = _asMap(campaignItem['campaign']);
      if (campaignPayload.isEmpty) {
        continue;
      }
      campaignPayload.putIfAbsent('referentialId', () => referentialId);
      final campaign = LocalCampaign.fromJson(campaignPayload);
      if (campaign.id.trim().isEmpty) {
        continue;
      }
      if (campaign.referentialId.trim().isNotEmpty &&
          campaign.referentialId != referentialId) {
        continue;
      }

      bundles.add(
        ServerCampaignBundle(
          campaign: campaign,
          criterionAnswers: _parseCriterionAnswers(campaignItem['answers']),
          assignments: _parseAssignments(
            campaignItem['assignments'],
            referentialId: referentialId,
            campaignId: campaign.id,
          ),
          activityEvents: _parseActivityEvents(
            campaignItem['activityLog'],
            referentialId: referentialId,
            campaignId: campaign.id,
          ),
        ),
      );
    }

    bundles.sort(
      (a, b) => b.campaign.updatedAt.compareTo(a.campaign.updatedAt),
    );
    return bundles;
  }

  Future<ServerCampaignBundle?> loadBundle({
    required String referentialId,
    required String campaignId,
  }) async {
    final bundles = await loadBundles(referentialId: referentialId);
    for (final bundle in bundles) {
      if (bundle.campaign.id == campaignId) {
        return bundle;
      }
    }
    return null;
  }

  Future<void> saveBundles({
    required String referentialId,
    required List<ServerCampaignBundle> bundles,
  }) async {
    final configuration = await configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      throw const ServerCampaignStoreException(
        'Terminal non autorisé : impossible d’écrire les campagnes serveur.',
      );
    }

    final payload = _buildPayload(
      referentialId: referentialId,
      configuration: configuration,
      bundles: bundles,
    );
    final push = await apiClient.pushPayload(
      baseUrl: configuration.apiBaseUrl,
      payload: payload,
      apiToken: configuration.apiToken,
    );

    if (!push.isAccepted) {
      throw ServerCampaignStoreException('${push.title} — ${push.message}');
    }
  }

  Future<void> updateBundle({
    required String referentialId,
    required String campaignId,
    required ServerCampaignBundle Function(ServerCampaignBundle bundle) update,
  }) async {
    final bundles = await loadBundles(referentialId: referentialId);
    var found = false;
    final updated = <ServerCampaignBundle>[];
    for (final bundle in bundles) {
      if (bundle.campaign.id == campaignId) {
        updated.add(update(bundle));
        found = true;
      } else {
        updated.add(bundle);
      }
    }
    if (!found) {
      throw ServerCampaignStoreException(
        'Campagne inconnue côté serveur : $campaignId',
      );
    }
    await saveBundles(referentialId: referentialId, bundles: updated);
  }

  Map<String, dynamic> _buildPayload({
    required String referentialId,
    required SyncConfiguration configuration,
    required List<ServerCampaignBundle> bundles,
  }) {
    final generatedAt = DateTime.now().toUtc();
    final activeUser = AppSessionManager.instance.activeUser;

    return <String, dynamic>{
      'schemaVersion': 1,
      'type': 'openirn.syncPush',
      'application': 'OpenIRN',
      'generatedAt': generatedAt.toIso8601String(),
      'sync': <String, dynamic>{
        'mode': 'server_only_client_update',
        'enabled': true,
        'apiBaseUrl': configuration.apiBaseUrl,
        'tenantId': configuration.tenantId,
        'deviceId': configuration.deviceId,
        'isConfigured': configuration.isConfigured,
      },
      if (activeUser != null) 'actor': activeUser.toJson(),
      'referential': <String, dynamic>{
        'id': referentialId,
        'version': 'server',
        'sourceUrl': '',
        'license': '',
        'checksumSha256': '',
        'criteriaCount': 0,
        'pillarsCount': 0,
      },
      'users': const <Map<String, dynamic>>[],
      'campaigns': bundles.map(_bundleToJson).toList(growable: false),
      'summary': <String, dynamic>{
        'campaignCount': bundles.length,
        'answerCount': bundles.fold<int>(
          0,
          (total, bundle) => total + bundle.criterionAnswers.length,
        ),
        'assignmentCount': bundles.fold<int>(
          0,
          (total, bundle) => total + bundle.assignments.length,
        ),
        'activityEventCount': bundles.fold<int>(
          0,
          (total, bundle) => total + bundle.activityEvents.length,
        ),
      },
    };
  }

  Map<String, dynamic> _bundleToJson(ServerCampaignBundle bundle) {
    return <String, dynamic>{
      'campaign': bundle.campaign.toJson(),
      'answers': bundle.criterionAnswers.values
          .where(
            (answer) =>
                answer.answer != IrnAnswer.notAnswered ||
                answer.justification.trim().isNotEmpty,
          )
          .map(_answerToJson)
          .toList(growable: false),
      'assignments': bundle.assignments
          .map((assignment) => assignment.toJson())
          .toList(growable: false),
      'activityLog': <String, dynamic>{
        'eventCount': bundle.activityEvents.length,
        'events': bundle.activityEvents
            .map((event) => event.toJson())
            .toList(growable: false),
      },
      'localSummary': <String, dynamic>{
        'answeredCount': bundle.criterionAnswers.values
            .where((answer) => answer.answer.isCounted)
            .length,
        'justifiedCount': bundle.criterionAnswers.values
            .where((answer) => answer.hasJustification)
            .length,
        'assignmentCount': bundle.assignments.length,
        'activityEventCount': bundle.activityEvents.length,
      },
    };
  }

  Map<String, dynamic> _answerToJson(CriterionAnswer answer) {
    return <String, dynamic>{
      'criterionId': answer.criterionId,
      'answer': answer.answer.name,
      'answerLabel': answer.answer.label,
      'justification': answer.justification.trim(),
      'hasJustification': answer.hasJustification,
    };
  }

  Map<String, CriterionAnswer> _parseCriterionAnswers(Object? rawAnswers) {
    if (rawAnswers is! List) {
      return <String, CriterionAnswer>{};
    }
    final answers = <String, CriterionAnswer>{};
    for (final rawAnswer in rawAnswers) {
      if (rawAnswer is! Map) {
        continue;
      }
      final payload = _asMap(rawAnswer);
      final criterionId = payload['criterionId']?.toString().trim() ?? '';
      if (criterionId.isEmpty) {
        continue;
      }
      final answer = _answerFromStoredValue(payload['answer']?.toString());
      final justification = payload['justification']?.toString() ?? '';
      if (answer == null) {
        continue;
      }
      if (answer == IrnAnswer.notAnswered && justification.trim().isEmpty) {
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

  List<CriterionAssignment> _parseAssignments(
    Object? rawAssignments, {
    required String referentialId,
    required String campaignId,
  }) {
    if (rawAssignments is! List) {
      return const <CriterionAssignment>[];
    }
    final assignments = <CriterionAssignment>[];
    for (final rawAssignment in rawAssignments) {
      if (rawAssignment is! Map) {
        continue;
      }
      final payload = _asMap(rawAssignment);
      payload.putIfAbsent('referentialId', () => referentialId);
      payload.putIfAbsent('campaignId', () => campaignId);
      final assignment = CriterionAssignment.fromJson(payload);
      if (assignment.criterionId.trim().isEmpty ||
          assignment.userId.trim().isEmpty) {
        continue;
      }
      assignments.add(assignment);
    }
    assignments.sort((a, b) => a.criterionId.compareTo(b.criterionId));
    return assignments;
  }

  List<LocalActivityEvent> _parseActivityEvents(
    Object? rawActivityLog, {
    required String referentialId,
    required String campaignId,
  }) {
    final eventsPayload = rawActivityLog is Map
        ? _asMap(rawActivityLog)['events']
        : rawActivityLog;
    if (eventsPayload is! List) {
      return const <LocalActivityEvent>[];
    }
    final events = <LocalActivityEvent>[];
    for (final rawEvent in eventsPayload) {
      if (rawEvent is! Map) {
        continue;
      }
      final payload = _asMap(rawEvent);
      payload.putIfAbsent('referentialId', () => referentialId);
      payload.putIfAbsent('campaignId', () => campaignId);
      final event = LocalActivityEvent.fromJson(payload);
      if (event.id.trim().isEmpty) {
        continue;
      }
      events.add(event);
    }
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }

  IrnAnswer? _answerFromStoredValue(String? value) {
    switch (value?.trim()) {
      case 'resilient':
      case 'R':
        return IrnAnswer.resilient;
      case 'nonResilient':
      case 'NR':
        return IrnAnswer.nonResilient;
      case 'notAnswered':
      case '':
        return IrnAnswer.notAnswered;
      default:
        return null;
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }
}
