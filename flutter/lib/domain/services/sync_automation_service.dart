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
    final comesFromThisDevice =
        latest.deviceId.trim().isNotEmpty &&
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
      serverSyncId: pull.snapshots.isEmpty
          ? null
          : pull.snapshots.first.serverSyncId,
      sourceDeviceId: pull.snapshots.isEmpty
          ? null
          : pull.snapshots.first.deviceId,
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

    // Depuis le mode server-only, les écritures métier partent directement vers
    // l’API au moment de l’action utilisateur. Ce hook reste appelé par certains
    // écrans historiques, mais il ne doit plus republier un état local.
    await _appendLog(
      configuration: configuration,
      type: SyncLogEventType.pushSucceeded,
      title: 'Mode serveur uniquement',
      message:
          'Aucun push local nécessaire : les campagnes sont déjà écrites directement côté serveur.',
    );

    return const SyncAutomationResult(
      outcome: SyncAutomationOutcome.upToDate,
      title: 'Mode serveur uniquement',
      message:
          'Les données métier sont lues et écrites directement via l’API OpenIRN.',
    );
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
        title: 'Snapshot serveur inutilisable',
        message: 'Le snapshot distant ne contient pas de payload importable.',
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      return const SyncAutomationResult(
        outcome: SyncAutomationOutcome.failed,
        title: 'Snapshot serveur inutilisable',
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

      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importSucceeded,
        title: 'Changement serveur détecté',
        message:
            '${result.campaignCount} campagne(s) disponible(s) côté serveur. Les écrans vont relire l’API.',
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
        campaignCount: result.campaignCount,
      );

      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.imported,
        title: 'Changement serveur détecté',
        message:
            '${result.campaignCount} campagne(s) disponible(s) côté serveur. Les écrans ont été invités à se rafraîchir.',
        serverSyncId: snapshot.serverSyncId,
        campaignCount: result.campaignCount,
      );
    } on SyncPullImportException catch (error) {
      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importFailed,
        title: 'Snapshot serveur refusé',
        message: error.message,
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.failed,
        title: 'Snapshot serveur refusé',
        message: error.message,
        serverSyncId: snapshot.serverSyncId,
      );
    } catch (error) {
      await _appendLog(
        configuration: configuration,
        type: SyncLogEventType.importFailed,
        title: 'Contrôle serveur impossible',
        message: error.toString(),
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      return SyncAutomationResult(
        outcome: SyncAutomationOutcome.failed,
        title: 'Contrôle serveur impossible',
        message: error.toString(),
        serverSyncId: snapshot.serverSyncId,
      );
    }
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
