import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../data/repositories/local_sync_log_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../models/app_user.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';
import '../models/sync_configuration.dart';
import '../models/sync_log_event.dart';
import 'sync_pull_import_service.dart';
import 'sync_push_payload_service.dart';

enum SyncAutomationOutcome {
  localOnly,
  offline,
  upToDate,
  pushed,
  imported,
  failed,
}

class SyncAutomationResult {
  final SyncAutomationOutcome outcome;
  final String title;
  final String message;
  final String? serverSyncId;
  final int? campaignCount;

  const SyncAutomationResult({
    required this.outcome,
    required this.title,
    required this.message,
    this.serverSyncId,
    this.campaignCount,
  });

  bool get isOnline =>
      outcome != SyncAutomationOutcome.localOnly &&
      outcome != SyncAutomationOutcome.offline;
  bool get importedRemoteSnapshot => outcome == SyncAutomationOutcome.imported;
  bool get pushedLocalSnapshot => outcome == SyncAutomationOutcome.pushed;
}

class SyncAutomationService {
  final LocalSyncConfigurationRepository configurationRepository;
  final LocalCampaignRepository campaignRepository;
  final LocalAssessmentRepository assessmentRepository;
  final LocalCriterionAssignmentRepository assignmentRepository;
  final LocalActivityRepository activityRepository;
  final LocalUserRepository userRepository;
  final LocalSessionRepository sessionRepository;
  final LocalSyncLogRepository syncLogRepository;
  final SyncPushPayloadService payloadService;
  final SyncPullImportService pullImportService;
  final OpenIrnApiClient apiClient;

  const SyncAutomationService({
    this.configurationRepository = const LocalSyncConfigurationRepository(),
    this.campaignRepository = const LocalCampaignRepository(),
    this.assessmentRepository = const LocalAssessmentRepository(),
    this.assignmentRepository = const LocalCriterionAssignmentRepository(),
    this.activityRepository = const LocalActivityRepository(),
    this.userRepository = const LocalUserRepository(),
    this.sessionRepository = const LocalSessionRepository(),
    this.syncLogRepository = const LocalSyncLogRepository(),
    this.payloadService = const SyncPushPayloadService(),
    this.pullImportService = const SyncPullImportService(),
    this.apiClient = const OpenIrnApiClient(),
  });

  Future<SyncAutomationResult> synchronize({
    required IrnReferential referential,
    AppUser? activeUser,
  }) async {
    final pullResult = await pullLatestIfRemoteNewer(referential: referential);
    switch (pullResult.outcome) {
      case SyncAutomationOutcome.imported:
      case SyncAutomationOutcome.localOnly:
      case SyncAutomationOutcome.offline:
      case SyncAutomationOutcome.failed:
        return pullResult;
      case SyncAutomationOutcome.upToDate:
      case SyncAutomationOutcome.pushed:
        return pushLocalSnapshot(
          referential: referential,
          activeUser: activeUser,
        );
    }
  }

  Future<SyncAutomationResult> pullLatestIfRemoteNewer({
    required IrnReferential referential,
  }) async {
    final configuration = await configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return const SyncAutomationResult(
        outcome: SyncAutomationOutcome.localOnly,
        title: 'Mode hors ligne uniquement',
        message: 'La synchronisation automatique est désactivée ou incomplète.',
      );
    }

    final status = await apiClient.loadSyncStatus(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
    await _appendLog(
      configuration: configuration,
      type: status.isAvailable
          ? SyncLogEventType.pullSucceeded
          : SyncLogEventType.pullFailed,
      title: 'Contrôle automatique serveur : ${status.title}',
      message: status.message,
      statusCode: status.statusCode,
      snapshotCount: status.snapshotCount,
      campaignCount: status.campaignCount,
      serverSyncId: status.latestSnapshot?.serverSyncId,
      sourceDeviceId: status.latestSnapshot?.deviceId,
    );

    if (!status.isAvailable) {
      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.offline,
        title: status.title,
        message: status.message,
      );
    }

    final latest = status.latestSnapshot;
    if (latest == null || latest.serverSyncId.trim().isEmpty) {
      return const SyncAutomationResult(
        outcome: SyncAutomationOutcome.upToDate,
        title: 'Aucun snapshot distant',
        message: 'Le serveur ne contient encore aucun snapshot exploitable.',
      );
    }

    final latestServerSyncId = latest.serverSyncId.trim();
    final syncEvents = await syncLogRepository.loadEvents();
    final knownLocally = syncEvents.any(
      (event) =>
          event.serverSyncId == latestServerSyncId &&
          (event.type == SyncLogEventType.pushSucceeded ||
              event.type == SyncLogEventType.importSucceeded),
    );
    final comesFromThisDevice = latest.deviceId.trim().isNotEmpty &&
        latest.deviceId.trim() == configuration.deviceId.trim();

    if (knownLocally || comesFromThisDevice) {
      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.upToDate,
        title: 'Données de ce terminal à jour',
        message: 'Le dernier snapshot serveur est déjà connu sur ce terminal.',
        serverSyncId: latestServerSyncId,
        campaignCount: latest.campaignCount,
      );
    }

    final pull = await apiClient.pullSnapshots(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      limit: 1,
    );
    await _appendLog(
      configuration: configuration,
      type: pull.status == OpenIrnApiPullStatus.available
          ? SyncLogEventType.pullSucceeded
          : SyncLogEventType.pullFailed,
      title: 'Récupération automatique : ${pull.title}',
      message: pull.message,
      statusCode: pull.statusCode,
      snapshotCount: pull.snapshots.length,
      campaignCount: pull.snapshots.fold<int>(
        0,
        (total, snapshot) => total + snapshot.campaignCount,
      ),
      serverSyncId:
          pull.snapshots.isEmpty ? null : pull.snapshots.first.serverSyncId,
      sourceDeviceId:
          pull.snapshots.isEmpty ? null : pull.snapshots.first.deviceId,
    );

    if (!pull.hasSnapshots) {
      return SyncAutomationResult(
        outcome: pull.status == OpenIrnApiPullStatus.unreachable
            ? SyncAutomationOutcome.offline
            : SyncAutomationOutcome.failed,
        title: pull.title,
        message: pull.message,
      );
    }

    return _replaceLocalDataWithSnapshot(
      configuration: configuration,
      referential: referential,
      snapshot: pull.snapshots.first,
    );
  }

  Stream<OpenIrnSyncEvent> watchRemoteEvents({
    String? sinceServerSyncId,
  }) async* {
    final configuration = await configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return;
    }

    yield* apiClient.watchSyncEvents(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      sinceServerSyncId: sinceServerSyncId,
    );
  }

  Future<SyncAutomationResult> pushLocalSnapshot({
    required IrnReferential referential,
    AppUser? activeUser,
  }) async {
    final configuration = await configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return const SyncAutomationResult(
        outcome: SyncAutomationOutcome.localOnly,
        title: 'Mode hors ligne uniquement',
        message: 'La synchronisation automatique est désactivée ou incomplète.',
      );
    }

    final users = await userRepository.ensureDefaultUsers();
    final actor = activeUser ?? await sessionRepository.getActiveUser();
    final campaigns = await campaignRepository.ensureDefaultCampaign(
      referentialId: referential.id,
      referentialVersion: referential.version,
    );
    final snapshots = await _loadCampaignSnapshots(
      referential: referential,
      campaigns: campaigns,
    );
    final payload = payloadService.buildPushPayload(
      referential: referential,
      configuration: configuration,
      activeUser: actor,
      users: users,
      campaigns: snapshots,
    );

    final push = await apiClient.pushPayload(
      baseUrl: configuration.apiBaseUrl,
      payload: payload,
      apiToken: configuration.apiToken,
    );
    final serverSyncId = push.responseBody?['serverSyncId']?.toString();
    await _appendLog(
      configuration: configuration,
      type: push.isAccepted
          ? SyncLogEventType.pushSucceeded
          : SyncLogEventType.pushFailed,
      title: 'Push automatique : ${push.title}',
      message: push.message,
      statusCode: push.statusCode,
      campaignCount: snapshots.length,
      serverSyncId: serverSyncId,
    );

    if (!push.isAccepted) {
      return SyncAutomationResult(
        outcome: push.status == OpenIrnApiPushStatus.unreachable
            ? SyncAutomationOutcome.offline
            : SyncAutomationOutcome.failed,
        title: push.title,
        message: push.message,
        serverSyncId: serverSyncId,
        campaignCount: snapshots.length,
      );
    }

    return SyncAutomationResult(
      outcome: SyncAutomationOutcome.pushed,
      title: 'Snapshot de ce terminal publié',
      message: serverSyncId == null || serverSyncId.isEmpty
          ? 'Le serveur a accepté la version de ce terminal.'
          : 'Le serveur a accepté la version de ce terminal : $serverSyncId.',
      serverSyncId: serverSyncId,
      campaignCount: snapshots.length,
    );
  }

  Future<List<CampaignSyncSnapshot>> _loadCampaignSnapshots({
    required IrnReferential referential,
    required List<LocalCampaign> campaigns,
  }) async {
    final snapshots = <CampaignSyncSnapshot>[];
    for (final campaign in campaigns) {
      final criterionAnswers = await assessmentRepository.loadCriterionAnswers(
        referentialId: referential.id,
        campaignId: campaign.id,
      );
      final assignments = await assignmentRepository.loadAssignments(
        referentialId: referential.id,
        campaignId: campaign.id,
      );
      final activityEvents = await activityRepository.loadEvents(
        referentialId: referential.id,
        campaignId: campaign.id,
      );
      snapshots.add(
        CampaignSyncSnapshot(
          campaign: campaign,
          criterionAnswers: criterionAnswers,
          assignments: assignments,
          activityEvents: activityEvents,
        ),
      );
    }
    return snapshots;
  }

  Future<SyncAutomationResult> _replaceLocalDataWithSnapshot({
    required SyncConfiguration configuration,
    required IrnReferential referential,
    required OpenIrnApiPullSnapshot snapshot,
  }) async {
    final payload = snapshot.payload;
    if (payload == null || payload.isEmpty) {
      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importFailed,
        title: 'Import automatique refusé',
        message: 'Le snapshot distant ne contient pas de payload importable.',
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      return const SyncAutomationResult(
        outcome: SyncAutomationOutcome.failed,
        title: 'Import automatique impossible',
        message: 'Le snapshot distant ne contient pas de payload importable.',
      );
    }

    try {
      final result = pullImportService.importSnapshotPayload(
        payload: payload,
        referential: referential,
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
        mode: SyncPullImportMode.replaceLocal,
      );

      await _mergeImportedUsers(result.users);
      await campaignRepository.saveCampaigns(
        referentialId: referential.id,
        campaigns: result.campaigns
            .map((campaign) => campaign.campaign)
            .toList(growable: false),
      );
      for (final campaign in result.campaigns) {
        await assessmentRepository.saveCriterionAnswers(
          referentialId: referential.id,
          campaignId: campaign.campaign.id,
          answers: campaign.criterionAnswers,
        );
        await assignmentRepository.saveAssignments(
          referentialId: referential.id,
          campaignId: campaign.campaign.id,
          assignments: campaign.assignments,
        );
        await activityRepository.saveEvents(
          referentialId: referential.id,
          campaignId: campaign.campaign.id,
          events: campaign.activityEvents,
        );
      }

      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importSucceeded,
        title: 'Snapshot distant appliqué automatiquement',
        message:
            '${result.campaignCount} campagne(s) remplacée(s) par la version serveur.',
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
        campaignCount: result.campaignCount,
      );

      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.imported,
        title: 'Version serveur appliquée',
        message:
            '${result.campaignCount} campagne(s) remplacée(s) par la dernière version serveur.',
        serverSyncId: snapshot.serverSyncId,
        campaignCount: result.campaignCount,
      );
    } on SyncPullImportException catch (error) {
      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importFailed,
        title: 'Import automatique refusé',
        message: error.message,
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.failed,
        title: 'Import automatique refusé',
        message: error.message,
        serverSyncId: snapshot.serverSyncId,
      );
    } catch (error) {
      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importFailed,
        title: 'Import automatique impossible',
        message: error.toString(),
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.failed,
        title: 'Import automatique impossible',
        message: error.toString(),
        serverSyncId: snapshot.serverSyncId,
      );
    }
  }

  Future<void> _mergeImportedUsers(List<AppUser> importedUsers) async {
    if (importedUsers.isEmpty) {
      return;
    }
    final existingUsers = await userRepository.ensureDefaultUsers();
    final usersById = <String, AppUser>{
      for (final user in existingUsers) user.id: user,
    };

    for (final importedUser in importedUsers) {
      if (importedUser.id == AppUser.defaultAdministratorId) {
        usersById.putIfAbsent(importedUser.id, () => importedUser);
        continue;
      }
      usersById[importedUser.id] = importedUser;
    }

    await userRepository.saveUsers(usersById.values.toList(growable: false));
  }

  Future<void> _appendLog({
    required SyncConfiguration configuration,
    required SyncLogEventType type,
    required String title,
    required String message,
    String? serverSyncId,
    String? sourceDeviceId,
    int? statusCode,
    int? campaignCount,
    int? snapshotCount,
  }) async {
    await syncLogRepository.appendEvent(
      SyncLogEvent.create(
        type: type,
        tenantId: configuration.tenantId,
        deviceId: configuration.deviceId,
        title: title,
        message: message,
        serverSyncId: serverSyncId,
        sourceDeviceId: sourceDeviceId,
        statusCode: statusCode,
        campaignCount: campaignCount,
        snapshotCount: snapshotCount,
      ),
    );
  }
}
