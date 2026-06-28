import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../data/repositories/local_sync_log_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/models/sync_log_event.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/sync_push_payload_service.dart';
import '../../domain/services/sync_pull_import_service.dart';
import '../../domain/services/access_policy_service.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_dialog.dart';

class SyncScreen extends StatefulWidget {
  final IrnReferential referential;

  const SyncScreen({required this.referential, super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _syncConfigurationRepository = const LocalSyncConfigurationRepository();
  final _campaignRepository = const LocalCampaignRepository();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _assignmentRepository = const LocalCriterionAssignmentRepository();
  final _activityRepository = const LocalActivityRepository();
  final _userRepository = const LocalUserRepository();
  final _sessionRepository = const LocalSessionRepository();
  final _syncLogRepository = const LocalSyncLogRepository();
  final _payloadService = const SyncPushPayloadService();
  final _pullImportService = const SyncPullImportService();
  final _apiClient = const OpenIrnApiClient();
  final _accessPolicy = const AccessPolicyService();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tenantIdController;
  late final TextEditingController _deviceIdController;
  late final TextEditingController _apiTokenController;
  bool _obscureApiToken = true;

  late Future<_SyncScreenStateData> _future;
  bool _enabled = false;
  bool _saving = false;
  bool _buildingPayload = false;
  bool _testingConnection = false;
  bool _pushingPayload = false;
  bool _pullingSnapshots = false;
  bool _pullingAndImportingLatest = false;
  bool _runningSmartSync = false;
  bool _clearingAuthorization = false;
  bool _loadingServerStatus = false;
  String? _importingSnapshotId;
  String? _payloadPreview;
  OpenIrnApiConnectionResult? _connectionResult;
  OpenIrnApiPushResult? _pushResult;
  OpenIrnApiPullResult? _pullResult;
  OpenIrnApiStatusResult? _serverStatusResult;
  _ServerFreshnessInfo? _serverFreshnessInfo;
  SyncPullImportResult? _lastImportResult;

  @override
  void initState() {
    super.initState();
    _tenantIdController = TextEditingController();
    _deviceIdController = TextEditingController();
    _apiTokenController = TextEditingController();
    _future = _load();
    _future.then((_) {
      if (mounted) {
        _loadServerStatus(showSnackBar: false);
      }
    });
  }

  @override
  void dispose() {
    _tenantIdController.dispose();
    _deviceIdController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  Future<_SyncScreenStateData> _load() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final activeUser = await _sessionRepository.getActiveUser();
    final users = await _userRepository.ensureDefaultUsers();
    final campaigns = await _campaignRepository.ensureDefaultCampaign(
      referentialId: widget.referential.id,
      referentialVersion: widget.referential.version,
    );
    final snapshots = await _loadCampaignSnapshots(campaigns);

    if (mounted) {
      _tenantIdController.text = configuration.tenantId;
      _deviceIdController.text = configuration.deviceId;
      _apiTokenController.text = configuration.apiToken;
      _enabled = configuration.enabled;
    }

    return _SyncScreenStateData(
      configuration: configuration,
      activeUser: activeUser,
      users: users,
      snapshots: snapshots,
    );
  }

  Future<List<CampaignSyncSnapshot>> _loadCampaignSnapshots(
    List<LocalCampaign> campaigns,
  ) async {
    final snapshots = <CampaignSyncSnapshot>[];
    for (final campaign in campaigns) {
      final criterionAnswers = await _assessmentRepository.loadCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      final assignments = await _assignmentRepository.loadAssignments(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      final activityEvents = await _activityRepository.loadEvents(
        referentialId: widget.referential.id,
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

  Future<void> _refresh() async {
    setState(() {
      _payloadPreview = null;
      _pushResult = null;
      _pullResult = null;
      _serverStatusResult = null;
      _serverFreshnessInfo = null;
      _lastImportResult = null;
      _pullingAndImportingLatest = false;
      _runningSmartSync = false;
      _future = _load();
    });
    await _future;
  }

  Future<void> _saveConfiguration() async {
    if (_enabled && _apiTokenController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autorise ce terminal avec un code d’appairage avant d’activer la synchronisation.',
          ),
        ),
      );
      return;
    }
    if (_apiTokenController.text.trim().isNotEmpty &&
        _apiTokenController.text.trim().length < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le jeton serveur doit contenir au moins 16 caractères.',
          ),
        ),
      );
      return;
    }
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    setState(() {
      _saving = true;
    });
    final configuration = SyncConfiguration.empty().copyWith(
      tenantId: _tenantIdController.text,
      deviceId: _deviceIdController.text,
      enabled: _enabled,
      apiToken: _apiTokenController.text,
    );
    final saved = await _syncConfigurationRepository.saveConfiguration(
      configuration,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _payloadPreview = null;
      _pushResult = null;
      _pullResult = null;
      _serverStatusResult = null;
      _serverFreshnessInfo = null;
      _tenantIdController.text = saved.tenantId;
      _deviceIdController.text = saved.deviceId;
      _apiTokenController.text = saved.apiToken;
      _future = _load();
    });
    AppSyncCoordinator.instance.start(referential: widget.referential);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration de synchronisation sauvegardée.'),
      ),
    );
  }

  Future<void> _resetDeviceId() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Régénérer l’identifiant appareil ?'),
        content: const ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            'Un nouvel identifiant sera généré. Cette action est utile uniquement si tu veux simuler un nouvel appareil client.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.refresh),
            label: const Text('Régénérer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final deviceId = await _syncConfigurationRepository.resetDeviceId();
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceIdController.text = deviceId;
      _payloadPreview = null;
      _pushResult = null;
      _pullResult = null;
      _serverStatusResult = null;
      _serverFreshnessInfo = null;
      _future = _load();
    });
  }

  Future<void> _forgetLocalAuthorization() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Oublier l’autorisation locale ?'),
        content: ResponsiveDialogContent(
          maxWidth: 680,
          child: Text(
            'OpenIRN va supprimer le jeton stocké sur ce terminal.\n\n'
            'Terminal : ${configuration.deviceId}\n'
            'Tenant : ${configuration.tenantId}\n\n'
            'Cette action ne révoque pas le terminal côté serveur. Elle sert à nettoyer ce poste après révocation serveur ou avant un nouvel appairage.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Oublier'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _clearingAuthorization = true;
    });

    try {
      final cleared = await _syncConfigurationRepository.saveConfiguration(
        SyncConfiguration.empty(deviceId: configuration.deviceId).copyWith(
          tenantId: configuration.tenantId,
          enabled: false,
          apiToken: '',
        ),
      );
      AppSyncCoordinator.instance.stop();

      if (!mounted) {
        return;
      }
      setState(() {
        _enabled = cleared.enabled;
        _tenantIdController.text = cleared.tenantId;
        _deviceIdController.text = cleared.deviceId;
        _apiTokenController.text = cleared.apiToken;
        _payloadPreview = null;
        _pushResult = null;
        _pullResult = null;
        _serverStatusResult = null;
        _serverFreshnessInfo = null;
        _future = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autorisation locale supprimée. Réappaire ce terminal pour resynchroniser.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearingAuthorization = false;
        });
      }
    }
  }

  Future<SyncConfiguration> _currentConfiguration() async {
    return _syncConfigurationRepository.loadConfiguration();
  }

  bool _isConfigurationFormValid() {
    final formState = _formKey.currentState;
    // On iOS/macOS, some sync actions can be triggered after a rebuild where the
    // form key is temporarily detached. In that case, use the last saved
    // configuration instead of crashing with a null check.
    return formState?.validate() ?? true;
  }

  Future<void> _appendSyncLogEvent({
    required SyncLogEventType type,
    required String title,
    required String message,
    String? serverSyncId,
    String? sourceDeviceId,
    int? statusCode,
    int? campaignCount,
    int? snapshotCount,
  }) async {
    final configuration = await _currentConfiguration();
    await _syncLogRepository.appendEvent(
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

  Future<Map<String, dynamic>> _buildPayloadMap(
    _SyncScreenStateData data,
  ) async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    return _payloadService.buildPushPayload(
      referential: widget.referential,
      configuration: configuration,
      activeUser: data.activeUser,
      users: data.users,
      campaigns: data.snapshots,
    );
  }

  Future<void> _buildPayload(_SyncScreenStateData data) async {
    setState(() {
      _buildingPayload = true;
      _pushResult = null;
    });
    final payload = await _buildPayloadMap(data);
    const encoder = JsonEncoder.withIndent('  ');
    if (!mounted) {
      return;
    }
    setState(() {
      _payloadPreview = encoder.convert(payload);
      _buildingPayload = false;
    });
  }

  Future<void> _pushPayload(_SyncScreenStateData data) async {
    if (!_isConfigurationFormValid()) {
      return;
    }
    setState(() {
      _pushingPayload = true;
      _pushResult = null;
    });

    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final payload = await _buildPayloadMap(data);
    const encoder = JsonEncoder.withIndent('  ');
    final result = await _apiClient.pushPayload(
      baseUrl: configuration.apiBaseUrl,
      payload: payload,
      apiToken: configuration.apiToken,
    );
    final responseBody = result.responseBody;
    await _appendSyncLogEvent(
      type: result.isAccepted
          ? SyncLogEventType.pushSucceeded
          : SyncLogEventType.pushFailed,
      title: result.title,
      message: result.message,
      serverSyncId: responseBody?['serverSyncId']?.toString(),
      statusCode: result.statusCode,
      campaignCount: data.campaignCount,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _payloadPreview = encoder.convert(payload);
      _pushingPayload = false;
      _pushResult = result;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.title)));
  }

  Future<void> _runSmartSync(_SyncScreenStateData data) async {
    if (!_isConfigurationFormValid()) {
      return;
    }
    setState(() {
      _runningSmartSync = true;
      _serverStatusResult = null;
      _serverFreshnessInfo = null;
    });

    try {
      final configuration = await _syncConfigurationRepository
          .loadConfiguration();
      final result = await _apiClient.loadSyncStatus(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );
      final syncEvents = await _syncLogRepository.loadEvents();
      final freshnessInfo = _ServerFreshnessInfo.fromStatus(
        statusResult: result,
        localDeviceId: configuration.deviceId,
        syncEvents: syncEvents,
      );

      await _appendSyncLogEvent(
        type: result.isAvailable
            ? SyncLogEventType.pullSucceeded
            : SyncLogEventType.pullFailed,
        title: 'Assistant de synchronisation : ${result.title}',
        message: result.message,
        statusCode: result.statusCode,
        snapshotCount: result.snapshotCount,
        campaignCount: result.campaignCount,
        serverSyncId: result.latestSnapshot?.serverSyncId,
        sourceDeviceId: result.latestSnapshot?.deviceId,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _serverStatusResult = result;
        _serverFreshnessInfo = freshnessInfo;
      });

      if (!result.isAvailable) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.title)));
        return;
      }

      if (freshnessInfo.state == _ServerFreshnessState.remoteNewer) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Snapshot distant détecté : récupération du dernier snapshot.',
            ),
          ),
        );
        await _pullAndImportLatestSnapshot();
        return;
      }

      await _pushPayload(data);
    } finally {
      if (mounted) {
        setState(() {
          _runningSmartSync = false;
        });
      }
    }
  }

  Future<void> _loadServerStatus({bool showSnackBar = true}) async {
    if (!_isConfigurationFormValid()) {
      return;
    }
    setState(() {
      _loadingServerStatus = true;
      _serverStatusResult = null;
    });

    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final result = await _apiClient.loadSyncStatus(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
    final syncEvents = await _syncLogRepository.loadEvents();
    final freshnessInfo = _ServerFreshnessInfo.fromStatus(
      statusResult: result,
      localDeviceId: configuration.deviceId,
      syncEvents: syncEvents,
    );

    await _appendSyncLogEvent(
      type: result.isAvailable
          ? SyncLogEventType.pullSucceeded
          : SyncLogEventType.pullFailed,
      title: result.title,
      message: result.message,
      statusCode: result.statusCode,
      snapshotCount: result.snapshotCount,
      campaignCount: result.campaignCount,
      serverSyncId: result.latestSnapshot?.serverSyncId,
      sourceDeviceId: result.latestSnapshot?.deviceId,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingServerStatus = false;
      _serverStatusResult = result;
      _serverFreshnessInfo = freshnessInfo;
    });
    if (showSnackBar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.title)));
    }
  }

  Future<void> _pullSnapshots() async {
    if (!_isConfigurationFormValid()) {
      return;
    }
    setState(() {
      _pullingSnapshots = true;
      _pullResult = null;
    });

    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final result = await _apiClient.pullSnapshots(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
    await _appendSyncLogEvent(
      type:
          result.status == OpenIrnApiPullStatus.rejected ||
              result.status == OpenIrnApiPullStatus.unreachable
          ? SyncLogEventType.pullFailed
          : SyncLogEventType.pullSucceeded,
      title: result.title,
      message: result.message,
      statusCode: result.statusCode,
      snapshotCount: result.snapshots.length,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _pullingSnapshots = false;
      _pullResult = result;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.title)));
  }

  Future<void> _pullAndImportLatestSnapshot() async {
    if (!_isConfigurationFormValid()) {
      return;
    }
    setState(() {
      _pullingAndImportingLatest = true;
      _pullResult = null;
      _lastImportResult = null;
    });

    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final result = await _apiClient.pullSnapshots(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      limit: 1,
    );
    await _appendSyncLogEvent(
      type:
          result.status == OpenIrnApiPullStatus.rejected ||
              result.status == OpenIrnApiPullStatus.unreachable
          ? SyncLogEventType.pullFailed
          : SyncLogEventType.pullSucceeded,
      title: result.title,
      message: '${result.message} Mode import rapide du dernier snapshot.',
      statusCode: result.statusCode,
      snapshotCount: result.snapshots.length,
      campaignCount: result.snapshots.fold<int>(
        0,
        (total, snapshot) => total + snapshot.campaignCount,
      ),
      serverSyncId: result.snapshots.isEmpty
          ? null
          : result.snapshots.first.serverSyncId,
      sourceDeviceId: result.snapshots.isEmpty
          ? null
          : result.snapshots.first.deviceId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _pullingAndImportingLatest = false;
      _pullResult = result;
    });

    if (!result.hasSnapshots) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.title)));
      return;
    }

    final latestSnapshot = result.snapshots.first;
    final payload = latestSnapshot.payload;
    if (payload == null || payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le dernier snapshot serveur ne contient pas de payload importable.',
          ),
        ),
      );
      return;
    }

    await _importSnapshot(latestSnapshot);
  }

  Future<void> _importSnapshot(OpenIrnApiPullSnapshot snapshot) async {
    final payload = snapshot.payload;
    if (payload == null || payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le snapshot sélectionné ne contient pas de payload importable.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Importer ce snapshot distant ?'),
        content: ResponsiveDialogContent(
          maxWidth: 680,
          child: Text(
            'OpenIRN va remplacer les campagnes par la version contenue dans ce snapshot.\n\n'
            'Snapshot : ${snapshot.serverSyncId}\n'
            'Appareil source : ${snapshot.deviceId}\n'
            'Campagnes : ${snapshot.campaignCount}\n\n'
            'Les données de ce terminal existantes seront remplacées par la dernière version serveur.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download_done_outlined),
            label: const Text('Importer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _importingSnapshotId = snapshot.serverSyncId;
      _lastImportResult = null;
    });

    try {
      final result = _pullImportService.importSnapshotPayload(
        payload: payload,
        referential: widget.referential,
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
        mode: SyncPullImportMode.replaceLocal,
      );

      await _mergeImportedUsers(result.users);
      await _campaignRepository.saveCampaigns(
        referentialId: widget.referential.id,
        campaigns: <LocalCampaign>[
          for (final importedCampaign in result.campaigns)
            importedCampaign.campaign,
        ],
      );

      for (final importedCampaign in result.campaigns) {
        await _assessmentRepository.saveCriterionAnswers(
          referentialId: widget.referential.id,
          campaignId: importedCampaign.campaign.id,
          answers: importedCampaign.criterionAnswers,
        );
        await _assignmentRepository.saveAssignments(
          referentialId: widget.referential.id,
          campaignId: importedCampaign.campaign.id,
          assignments: importedCampaign.assignments,
        );
        await _activityRepository.saveEvents(
          referentialId: widget.referential.id,
          campaignId: importedCampaign.campaign.id,
          events: importedCampaign.activityEvents,
        );
      }
      await _appendSyncLogEvent(
        type: SyncLogEventType.importSucceeded,
        title: 'Snapshot distant importé',
        message:
            '${result.campaignCount} campagne(s) remplacée(s) par la version serveur.',
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
        campaignCount: result.campaignCount,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _importingSnapshotId = null;
        _lastImportResult = result;
        _future = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.campaignCount} campagne(s) remplacée(s) par la version serveur.',
          ),
        ),
      );
    } on SyncPullImportException catch (error) {
      await _appendSyncLogEvent(
        type: SyncLogEventType.importFailed,
        title: 'Import distant refusé',
        message: error.message,
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _importingSnapshotId = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      await _appendSyncLogEvent(
        type: SyncLogEventType.importFailed,
        title: 'Import distant impossible',
        message: error.toString(),
        serverSyncId: snapshot.serverSyncId,
        sourceDeviceId: snapshot.deviceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _importingSnapshotId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import distant impossible : $error')),
      );
    }
  }

  Future<void> _mergeImportedUsers(List<AppUser> importedUsers) async {
    if (importedUsers.isEmpty) {
      return;
    }
    final existingUsers = await _userRepository.ensureDefaultUsers();
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

    await _userRepository.saveUsers(usersById.values.toList(growable: false));
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionResult = null;
    });
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final result = await _apiClient.testConnection(
      baseUrl: configuration.apiBaseUrl,
    );
    await _appendSyncLogEvent(
      type: SyncLogEventType.connectionTest,
      title: result.title,
      message: result.message,
      statusCode: result.statusCode,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _testingConnection = false;
      _connectionResult = result;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.title)));
  }

  Future<void> _copyPayload() async {
    final payload = _payloadPreview;
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payload de synchronisation copié.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Synchronisation API'),
      body: FutureBuilder<_SyncScreenStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return _ErrorState(
              error: 'État de synchronisation vide.',
              onRetry: _refresh,
            );
          }

          final canManageSync = _accessPolicy.canManageCampaigns(
            data.activeUser,
          );

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _IntroCard(configuration: data.configuration),
                  const SizedBox(height: 12),
                  _CurrentDeviceCard(configuration: data.configuration),
                  const SizedBox(height: 12),
                  _ServerStatusCard(
                    loadingServerStatus: _loadingServerStatus,
                    statusResult: _serverStatusResult,
                    freshnessInfo: _serverFreshnessInfo,
                    onLoadServerStatus: _loadServerStatus,
                  ),
                  if (canManageSync) ...[
                    const SizedBox(height: 12),
                    _SmartSyncCard(
                      runningSmartSync: _runningSmartSync,
                      pushingPayload: _pushingPayload,
                      pullingAndImportingLatest: _pullingAndImportingLatest,
                      importingSnapshotId: _importingSnapshotId,
                      freshnessInfo: _serverFreshnessInfo,
                      onRunSmartSync: () => _runSmartSync(data),
                    ),
                    const SizedBox(height: 12),
                    _ConfigurationCard(
                      formKey: _formKey,
                      tenantIdController: _tenantIdController,
                      deviceIdController: _deviceIdController,
                      apiTokenController: _apiTokenController,
                      obscureApiToken: _obscureApiToken,
                      configuration: data.configuration,
                      enabled: _enabled,
                      saving: _saving,
                      testingConnection: _testingConnection,
                      connectionResult: _connectionResult,
                      clearingAuthorization: _clearingAuthorization,
                      onForgetLocalAuthorization: _forgetLocalAuthorization,
                      onObscureApiTokenChanged: (value) => setState(() {
                        _obscureApiToken = value;
                      }),
                      onEnabledChanged: (value) => setState(() {
                        _enabled = value;
                        _payloadPreview = null;
                        _pushResult = null;
                        _pullResult = null;
                        _serverStatusResult = null;
                        _serverFreshnessInfo = null;
                      }),
                      onSave: _saveConfiguration,
                      onTestConnection: _testConnection,
                      onResetDeviceId: _resetDeviceId,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_mode_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Interface simplifiée',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'La synchronisation courante est automatique. Les outils techniques de push/pull restent retirés de l’interface utilisateur.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Offstage(
                      offstage: true,
                      child: Column(
                        children: [
                          _LocalDataCard(data: data),
                          _PayloadCard(
                            payloadPreview: _payloadPreview,
                            buildingPayload: _buildingPayload,
                            pushingPayload: _pushingPayload,
                            pushResult: _pushResult,
                            onBuildPayload: () => _buildPayload(data),
                            onPushPayload: () => _pushPayload(data),
                            onCopyPayload: _copyPayload,
                          ),
                          _RemoteSnapshotsCard(
                            pullingSnapshots: _pullingSnapshots,
                            pullingAndImportingLatest:
                                _pullingAndImportingLatest,
                            importingSnapshotId: _importingSnapshotId,
                            pullResult: _pullResult,
                            lastImportResult: _lastImportResult,
                            onPullSnapshots: _pullSnapshots,
                            onPullAndImportLatestSnapshot:
                                _pullAndImportLatestSnapshot,
                            onImportSnapshot: _importSnapshot,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const _NonAdministratorSyncNotice(),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _ServerFreshnessState {
  notChecked,
  noRemoteSnapshot,
  upToDate,
  remoteNewer,
  localDeviceUntracked,
  unavailable,
}

class _ServerFreshnessInfo {
  final _ServerFreshnessState state;
  final String title;
  final String message;
  final String? latestServerSyncId;
  final String? latestDeviceId;

  const _ServerFreshnessInfo({
    required this.state,
    required this.title,
    required this.message,
    this.latestServerSyncId,
    this.latestDeviceId,
  });

  bool get shouldPull => state == _ServerFreshnessState.remoteNewer;
  bool get isOk =>
      state == _ServerFreshnessState.upToDate ||
      state == _ServerFreshnessState.noRemoteSnapshot;

  factory _ServerFreshnessInfo.fromStatus({
    required OpenIrnApiStatusResult statusResult,
    required String localDeviceId,
    required List<SyncLogEvent> syncEvents,
  }) {
    if (!statusResult.isAvailable) {
      return const _ServerFreshnessInfo(
        state: _ServerFreshnessState.unavailable,
        title: 'Comparaison impossible',
        message:
            'Le statut serveur n’est pas disponible. Corrige la connexion ou le token, puis relance le contrôle.',
      );
    }

    final latest = statusResult.latestSnapshot;
    if (latest == null || latest.serverSyncId.trim().isEmpty) {
      return const _ServerFreshnessInfo(
        state: _ServerFreshnessState.noRemoteSnapshot,
        title: 'Aucun snapshot serveur',
        message:
            'Le serveur ne contient pas encore de snapshot pour ce tenant.',
      );
    }

    final latestServerSyncId = latest.serverSyncId.trim();
    final knownLocally = syncEvents.any(
      (event) =>
          event.serverSyncId == latestServerSyncId &&
          (event.type == SyncLogEventType.pushSucceeded ||
              event.type == SyncLogEventType.importSucceeded),
    );

    if (knownLocally) {
      return _ServerFreshnessInfo(
        state: _ServerFreshnessState.upToDate,
        title: 'Synchronisation à jour',
        message:
            'Le dernier snapshot serveur est déjà connu sur ce terminal par un push ou un import.',
        latestServerSyncId: latestServerSyncId,
        latestDeviceId: latest.deviceId,
      );
    }

    final normalizedLocalDeviceId = localDeviceId.trim();
    final latestDeviceId = latest.deviceId.trim();
    if (latestDeviceId.isNotEmpty &&
        latestDeviceId == normalizedLocalDeviceId) {
      return _ServerFreshnessInfo(
        state: _ServerFreshnessState.localDeviceUntracked,
        title: 'Snapshot de cet appareil non journalisé',
        message:
            'Le serveur indique que le dernier snapshot vient de cet appareil, mais il n’apparaît pas dans le journal de ce terminal. Cela peut arriver après une réinstallation ou un nettoyage local.',
        latestServerSyncId: latestServerSyncId,
        latestDeviceId: latestDeviceId,
      );
    }

    return _ServerFreshnessInfo(
      state: _ServerFreshnessState.remoteNewer,
      title: 'Snapshot distant plus récent disponible',
      message:
          'Le serveur contient un snapshot qui n’a pas encore été importé sur ce terminal. Utilise “Récupérer”, puis “Importer” sur le snapshot concerné.',
      latestServerSyncId: latestServerSyncId,
      latestDeviceId: latestDeviceId.isEmpty ? null : latestDeviceId,
    );
  }
}

class _SyncScreenStateData {
  final SyncConfiguration configuration;
  final AppUser activeUser;
  final List<AppUser> users;
  final List<CampaignSyncSnapshot> snapshots;

  const _SyncScreenStateData({
    required this.configuration,
    required this.activeUser,
    required this.users,
    required this.snapshots,
  });

  int get campaignCount => snapshots.length;
  int get answerCount => snapshots.fold<int>(
    0,
    (total, snapshot) => total + snapshot.criterionAnswers.length,
  );
  int get assignmentCount => snapshots.fold<int>(
    0,
    (total, snapshot) => total + snapshot.assignments.length,
  );
  int get activityEventCount => snapshots.fold<int>(
    0,
    (total, snapshot) => total + snapshot.activityEvents.length,
  );
}

class _IntroCard extends StatelessWidget {
  final SyncConfiguration configuration;

  const _IntroCard({required this.configuration});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              configuration.isConfigured
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 38,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Préparation synchronisation API',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'OpenIRN fonctionne maintenant en mode automatisé : l’application contrôle régulièrement le serveur, '
                    'importe automatiquement la dernière version distante quand elle existe, puis publie les modifications de ce terminal.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(
                          configuration.isConfigured
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          size: 18,
                        ),
                        label: Text(
                          configuration.isConfigured
                              ? 'Configuration prête'
                              : 'Configuration incomplète',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'Mode : ${configuration.enabled ? 'activé' : 'désactivé'}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentDeviceCard extends StatelessWidget {
  final SyncConfiguration configuration;

  const _CurrentDeviceCard({required this.configuration});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDeviceToken = configuration.usesDeviceToken;
    final hasToken = configuration.hasApiToken;
    final icon = hasToken
        ? isDeviceToken
              ? Icons.verified_user_outlined
              : Icons.admin_panel_settings_outlined
        : Icons.phonelink_lock_outlined;
    final containerColor = hasToken
        ? isDeviceToken
              ? colorScheme.primaryContainer
              : colorScheme.tertiaryContainer
        : colorScheme.errorContainer;
    final textColor = hasToken
        ? isDeviceToken
              ? colorScheme.onPrimaryContainer
              : colorScheme.onTertiaryContainer
        : colorScheme.onErrorContainer;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Terminal courant',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: containerColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            configuration.authorizationModeLabel,
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      ),
                      Chip(label: Text('Tenant : ${configuration.tenantId}')),
                      Chip(
                        label: Text(
                          configuration.enabled
                              ? 'Synchronisation activée'
                              : 'Synchronisation désactivée',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText('Identifiant : ${configuration.deviceId}'),
                  const SizedBox(height: 4),
                  Text(configuration.authorizationModeDescription),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorizationStatusBox extends StatelessWidget {
  final SyncConfiguration configuration;

  const _AuthorizationStatusBox({required this.configuration});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = configuration.usesDeviceToken
        ? colorScheme.primary
        : configuration.usesLegacyBearerToken
        ? colorScheme.tertiary
        : colorScheme.error;
    final icon = configuration.usesDeviceToken
        ? Icons.verified_user_outlined
        : configuration.usesLegacyBearerToken
        ? Icons.warning_amber_outlined
        : Icons.lock_open_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configuration.authorizationModeLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(configuration.authorizationModeDescription),
                const SizedBox(height: 4),
                Text('Jeton : ${configuration.maskedApiToken}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigurationCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController tenantIdController;
  final TextEditingController deviceIdController;
  final TextEditingController apiTokenController;
  final bool obscureApiToken;
  final SyncConfiguration configuration;
  final bool enabled;
  final bool saving;
  final bool testingConnection;
  final OpenIrnApiConnectionResult? connectionResult;
  final bool clearingAuthorization;
  final VoidCallback onForgetLocalAuthorization;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onObscureApiTokenChanged;
  final VoidCallback onSave;
  final VoidCallback onTestConnection;
  final VoidCallback onResetDeviceId;

  const _ConfigurationCard({
    required this.formKey,
    required this.tenantIdController,
    required this.deviceIdController,
    required this.apiTokenController,
    required this.obscureApiToken,
    required this.configuration,
    required this.enabled,
    required this.saving,
    required this.testingConnection,
    required this.connectionResult,
    required this.clearingAuthorization,
    required this.onForgetLocalAuthorization,
    required this.onEnabledChanged,
    required this.onObscureApiTokenChanged,
    required this.onSave,
    required this.onTestConnection,
    required this.onResetDeviceId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_ethernet_outlined),
                  const SizedBox(width: 10),
                  Text(
                    'Configuration API',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activer la synchronisation'),
                subtitle: const Text(
                  'Prépare les payloads pour le serveur OpenIRN hébergé sur l’infrastructure Archoad.',
                ),
                value: enabled,
                onChanged: onEnabledChanged,
              ),
              const SizedBox(height: 10),
              _FixedApiEndpointTile(
                configuration: configuration,
                testingConnection: testingConnection,
                connectionResult: connectionResult,
                onTestConnection: onTestConnection,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: tenantIdController,
                decoration: const InputDecoration(
                  labelText: 'Identifiant organisation / tenant',
                  hintText: SyncConfiguration.defaultTenantId,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (!enabled) {
                    return null;
                  }
                  if (value == null || value.trim().isEmpty) {
                    return 'Le tenant est obligatoire lorsque la synchronisation est activée.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              _AuthorizationStatusBox(configuration: configuration),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Procédure d’urgence bearer'),
                subtitle: const Text(
                  'À utiliser uniquement pour migration ou dépannage serveur.',
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  const Text(
                    'L’usage normal est l’autorisation par code d’appairage depuis Administration → Terminaux autorisés. '
                    'La saisie manuelle du bearer reste disponible pour récupérer un environnement ou migrer un ancien terminal.',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: apiTokenController,
                    obscureText: obscureApiToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    decoration: InputDecoration(
                      labelText: 'Bearer / jeton serveur',
                      helperText:
                          'Masqué dans l’usage normal. Ne pas transmettre aux utilisateurs.',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: obscureApiToken
                            ? 'Afficher le jeton'
                            : 'Masquer le jeton',
                        onPressed: () =>
                            onObscureApiTokenChanged(!obscureApiToken),
                        icon: Icon(
                          obscureApiToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final token = value?.trim() ?? '';
                      if (token.isNotEmpty && token.length < 16) {
                        return 'Le jeton serveur doit contenir au moins 16 caractères.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: clearingAuthorization
                          ? null
                          : onForgetLocalAuthorization,
                      icon: clearingAuthorization
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.logout_outlined),
                      label: Text(
                        clearingAuthorization
                            ? 'Nettoyage...'
                            : 'Oublier l’autorisation locale',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: deviceIdController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Identifiant appareil',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Régénérer l’identifiant appareil',
                    onPressed: onResetDeviceId,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(saving ? 'Sauvegarde…' : 'Sauvegarder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixedApiEndpointTile extends StatelessWidget {
  final SyncConfiguration configuration;
  final bool testingConnection;
  final OpenIrnApiConnectionResult? connectionResult;
  final VoidCallback onTestConnection;

  const _FixedApiEndpointTile({
    required this.configuration,
    required this.testingConnection,
    required this.connectionResult,
    required this.onTestConnection,
  });

  @override
  Widget build(BuildContext context) {
    final result = connectionResult;
    final colorScheme = Theme.of(context).colorScheme;
    final resultColor = result == null
        ? null
        : result.isReady
        ? colorScheme.primary
        : result.isReachable
        ? colorScheme.tertiary
        : colorScheme.error;
    final resultIcon = result == null
        ? Icons.cloud_outlined
        : result.isReady
        ? Icons.cloud_done_outlined
        : result.isReachable
        ? Icons.cloud_sync_outlined
        : Icons.cloud_off_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.dns_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Serveur API OpenIRN',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(configuration.apiBaseUrl),
                    const SizedBox(height: 4),
                    const Text(
                      'L’URL serveur est fixe pour OpenIRN. Elle n’est plus saisie par les utilisateurs.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: testingConnection ? null : onTestConnection,
                icon: testingConnection
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_outlined),
                label: Text(testingConnection ? 'Test…' : 'Tester'),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(resultIcon, color: resultColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: resultColor),
                      ),
                      const SizedBox(height: 3),
                      Text(result.message),
                      const SizedBox(height: 3),
                      Text('URL testée : ${result.url}'),
                      if (result.statusCode != null)
                        Text('HTTP ${result.statusCode}'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LocalDataCard extends StatelessWidget {
  final _SyncScreenStateData data;

  const _LocalDataCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 10),
                Text(
                  'Données de ce terminal prêtes à synchroniser',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Session : ${data.activeUser.displayName}')),
                Chip(label: Text(data.activeUser.role.label)),
                Chip(label: Text('Utilisateurs : ${data.users.length}')),
                Chip(label: Text('Campagnes : ${data.campaignCount}')),
                Chip(label: Text('Réponses : ${data.answerCount}')),
                Chip(label: Text('Affectations : ${data.assignmentCount}')),
                Chip(label: Text('Évènements : ${data.activityEventCount}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveCardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> actions;

  const _ResponsiveCardHeader({
    required this.icon,
    required this.title,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final titleRow = Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        final actionWrap = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          children: actions,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleRow, const SizedBox(height: 10), actionWrap],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleRow),
            const SizedBox(width: 12),
            Flexible(child: actionWrap),
          ],
        );
      },
    );
  }
}

class _PayloadCard extends StatelessWidget {
  final String? payloadPreview;
  final bool buildingPayload;
  final bool pushingPayload;
  final OpenIrnApiPushResult? pushResult;
  final VoidCallback onBuildPayload;
  final VoidCallback onPushPayload;
  final VoidCallback onCopyPayload;

  const _PayloadCard({
    required this.payloadPreview,
    required this.buildingPayload,
    required this.pushingPayload,
    required this.pushResult,
    required this.onBuildPayload,
    required this.onPushPayload,
    required this.onCopyPayload,
  });

  @override
  Widget build(BuildContext context) {
    final payload = payloadPreview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResponsiveCardHeader(
              icon: Icons.api_outlined,
              title: 'Payload /sync/push',
              actions: [
                TextButton.icon(
                  onPressed: buildingPayload ? null : onBuildPayload,
                  icon: buildingPayload
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.data_object),
                  label: Text(buildingPayload ? 'Préparation…' : 'Préparer'),
                ),
                FilledButton.icon(
                  onPressed: pushingPayload ? null : onPushPayload,
                  icon: pushingPayload
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(pushingPayload ? 'Envoi…' : 'Envoyer'),
                ),
                FilledButton.tonalIcon(
                  onPressed: payload == null ? null : onCopyPayload,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copier'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Le payload peut être inspecté localement, copié, ou envoyé au endpoint serveur /sync/push. '
              'Cette première version pousse un snapshot complet ; l’authentification forte et la résolution de conflits viendront ensuite.',
            ),
            if (pushResult != null) ...[
              const SizedBox(height: 12),
              _PushResultNotice(result: pushResult!),
            ],
            const SizedBox(height: 12),
            if (payload == null)
              const _EmptyPayloadNotice()
            else
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 360),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    payload,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PushResultNotice extends StatelessWidget {
  final OpenIrnApiPushResult result;

  const _PushResultNotice({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = result.isAccepted ? colorScheme.primary : colorScheme.error;
    final icon = result.isAccepted
        ? Icons.cloud_done_outlined
        : Icons.cloud_off_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 3),
                Text(result.message),
                const SizedBox(height: 3),
                Text('URL : ${result.url}'),
                if (result.statusCode != null)
                  Text('HTTP ${result.statusCode}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPayloadNotice extends StatelessWidget {
  const _EmptyPayloadNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.info_outline),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Clique sur “Préparer” pour générer un exemple de payload de synchronisation.',
          ),
        ),
      ],
    );
  }
}

class _NonAdministratorSyncNotice extends StatelessWidget {
  const _NonAdministratorSyncNotice();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Les paramètres serveur et le token API sont réservés aux administrateurs et pilotes IRN. '
                'La synchronisation est automatique : cette page affiche uniquement l’état détaillé de connexion.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartSyncCard extends StatelessWidget {
  final bool runningSmartSync;
  final bool pushingPayload;
  final bool pullingAndImportingLatest;
  final String? importingSnapshotId;
  final _ServerFreshnessInfo? freshnessInfo;
  final VoidCallback onRunSmartSync;

  const _SmartSyncCard({
    required this.runningSmartSync,
    required this.pushingPayload,
    required this.pullingAndImportingLatest,
    required this.importingSnapshotId,
    required this.freshnessInfo,
    required this.onRunSmartSync,
  });

  @override
  Widget build(BuildContext context) {
    final busy =
        runningSmartSync ||
        pushingPayload ||
        pullingAndImportingLatest ||
        importingSnapshotId != null;
    final info = freshnessInfo;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResponsiveCardHeader(
              icon: Icons.sync_outlined,
              title: 'Synchronisation automatique',
              actions: [
                FilledButton.icon(
                  onPressed: busy ? null : onRunSmartSync,
                  icon: runningSmartSync
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_outlined),
                  label: Text(
                    runningSmartSync
                        ? 'Synchronisation…'
                        : 'Synchroniser maintenant',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Ce mode applique la logique automatique : contrôle du dernier snapshot serveur, '
              'récupération de la version distante lorsqu’elle est plus récente, sinon publication de la version de ce terminal.',
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    info == null
                        ? Icons.info_outline
                        : info.shouldPull
                        ? Icons.download_for_offline_outlined
                        : Icons.cloud_upload_outlined,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      info == null
                          ? 'Aucun statut serveur récent : le bouton lancera d’abord un contrôle serveur.'
                          : info.shouldPull
                          ? 'Action recommandée : importer le dernier snapshot distant avant de pousser de nouvelles données.'
                          : 'Action recommandée : pousser le snapshot de ce terminal vers le serveur.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerStatusCard extends StatelessWidget {
  final bool loadingServerStatus;
  final OpenIrnApiStatusResult? statusResult;
  final _ServerFreshnessInfo? freshnessInfo;
  final VoidCallback onLoadServerStatus;

  const _ServerStatusCard({
    required this.loadingServerStatus,
    required this.statusResult,
    required this.freshnessInfo,
    required this.onLoadServerStatus,
  });

  @override
  Widget build(BuildContext context) {
    final result = statusResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResponsiveCardHeader(
              icon: Icons.cloud_sync_outlined,
              title: 'Statut serveur /sync/status',
              actions: [
                FilledButton.tonalIcon(
                  onPressed: loadingServerStatus ? null : onLoadServerStatus,
                  icon: loadingServerStatus
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.query_stats_outlined),
                  label: Text(
                    loadingServerStatus ? 'Lecture…' : 'Statut serveur',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Ce contrôle interroge le serveur sans rapatrier les payloads complets. '
              'Il permet de connaître le dernier snapshot accepté côté API et les compteurs du tenant configuré.',
            ),
            const SizedBox(height: 12),
            if (result == null)
              const Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clique sur “Statut serveur” pour interroger /sync/status.',
                    ),
                  ),
                ],
              )
            else ...[
              _ServerStatusNotice(result: result),
              if (freshnessInfo != null) ...[
                const SizedBox(height: 12),
                _ServerFreshnessNotice(info: freshnessInfo!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ServerFreshnessNotice extends StatelessWidget {
  final _ServerFreshnessInfo info;

  const _ServerFreshnessNotice({required this.info});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (info.state) {
      _ServerFreshnessState.upToDate => colorScheme.primary,
      _ServerFreshnessState.noRemoteSnapshot => colorScheme.tertiary,
      _ServerFreshnessState.remoteNewer => colorScheme.error,
      _ServerFreshnessState.localDeviceUntracked => colorScheme.tertiary,
      _ServerFreshnessState.unavailable => colorScheme.error,
      _ServerFreshnessState.notChecked => colorScheme.outline,
    };
    final icon = switch (info.state) {
      _ServerFreshnessState.upToDate => Icons.verified_outlined,
      _ServerFreshnessState.noRemoteSnapshot => Icons.cloud_queue_outlined,
      _ServerFreshnessState.remoteNewer => Icons.sync_problem_outlined,
      _ServerFreshnessState.localDeviceUntracked =>
        Icons.history_toggle_off_outlined,
      _ServerFreshnessState.unavailable => Icons.error_outline,
      _ServerFreshnessState.notChecked => Icons.info_outline,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 3),
                Text(info.message),
                if (info.latestServerSyncId != null ||
                    info.latestDeviceId != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (info.latestServerSyncId != null)
                        Chip(
                          label: Text('Dernier : ${info.latestServerSyncId}'),
                        ),
                      if (info.latestDeviceId != null)
                        Chip(label: Text('Appareil : ${info.latestDeviceId}')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerStatusNotice extends StatelessWidget {
  final OpenIrnApiStatusResult result;

  const _ServerStatusNotice({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = result.isAvailable ? colorScheme.primary : colorScheme.error;
    final icon = result.isAvailable
        ? Icons.cloud_done_outlined
        : Icons.cloud_off_outlined;
    final latest = result.latestSnapshot;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: color),
                    ),
                    const SizedBox(height: 3),
                    Text(result.message),
                    const SizedBox(height: 3),
                    Text('URL : ${result.url}'),
                    if (result.statusCode != null)
                      Text('HTTP ${result.statusCode}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  'Tenant : ${result.tenantId.isEmpty ? '—' : result.tenantId}',
                ),
              ),
              Chip(label: Text('Snapshots : ${result.snapshotCount}')),
              Chip(label: Text('Appareils : ${result.deviceCount}')),
              Chip(label: Text('Campagnes : ${result.campaignCount}')),
              if (result.serverTime != null)
                Chip(
                  label: Text('Serveur : ${_formatDate(result.serverTime!)}'),
                ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 12),
            Text(
              'Dernier snapshot',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('serverSyncId : ${latest.serverSyncId}')),
                Chip(label: Text('Appareil : ${latest.deviceId}')),
                Chip(label: Text('${latest.campaignCount} campagne(s)')),
                if (latest.receivedAt != null)
                  Chip(
                    label: Text('Reçu : ${_formatDate(latest.receivedAt!)}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _RemoteSnapshotsCard extends StatelessWidget {
  final bool pullingSnapshots;
  final bool pullingAndImportingLatest;
  final String? importingSnapshotId;
  final OpenIrnApiPullResult? pullResult;
  final SyncPullImportResult? lastImportResult;
  final VoidCallback onPullSnapshots;
  final VoidCallback onPullAndImportLatestSnapshot;
  final ValueChanged<OpenIrnApiPullSnapshot> onImportSnapshot;

  const _RemoteSnapshotsCard({
    required this.pullingSnapshots,
    required this.pullingAndImportingLatest,
    required this.importingSnapshotId,
    required this.pullResult,
    required this.lastImportResult,
    required this.onPullSnapshots,
    required this.onPullAndImportLatestSnapshot,
    required this.onImportSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    final result = pullResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResponsiveCardHeader(
              icon: Icons.cloud_download_outlined,
              title: 'Snapshots distants /sync/pull',
              actions: [
                FilledButton.tonalIcon(
                  onPressed: pullingSnapshots ? null : onPullSnapshots,
                  icon: pullingSnapshots
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: Text(pullingSnapshots ? 'Récupération…' : 'Récupérer'),
                ),
                FilledButton.icon(
                  onPressed:
                      pullingSnapshots ||
                          pullingAndImportingLatest ||
                          importingSnapshotId != null
                      ? null
                      : onPullAndImportLatestSnapshot,
                  icon: pullingAndImportingLatest
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_done_outlined),
                  label: Text(
                    pullingAndImportingLatest
                        ? 'Préparation…'
                        : 'Importer le dernier',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Cette étape récupère les derniers snapshots stockés côté serveur pour le tenant configuré. '
              'Tu peux importer explicitement un snapshot distant sous forme de nouvelles campagnes, ou utiliser “Importer le dernier” pour récupérer puis proposer automatiquement le snapshot le plus récent.',
            ),
            const SizedBox(height: 12),
            if (result == null)
              const Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clique sur “Récupérer” pour interroger le endpoint /sync/pull.',
                    ),
                  ),
                ],
              )
            else ...[
              _PullResultNotice(result: result),
              if (result.hasSnapshots) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Snapshots : ${result.snapshots.length}')),
                    Chip(
                      label: Text(
                        'Dernier : ${result.snapshots.first.serverSyncId}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Appareil : ${result.snapshots.first.deviceId}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _RemoteSnapshotList(
                  snapshots: result.snapshots,
                  importingSnapshotId: importingSnapshotId,
                  onImportSnapshot: onImportSnapshot,
                ),
                const SizedBox(height: 12),
                _RemoteSnapshotPreview(result: result),
              ],
              if (lastImportResult != null) ...[
                const SizedBox(height: 12),
                _ImportResultNotice(result: lastImportResult!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PullResultNotice extends StatelessWidget {
  final OpenIrnApiPullResult result;

  const _PullResultNotice({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (result.status) {
      OpenIrnApiPullStatus.available => colorScheme.primary,
      OpenIrnApiPullStatus.empty => colorScheme.tertiary,
      OpenIrnApiPullStatus.rejected => colorScheme.error,
      OpenIrnApiPullStatus.unreachable => colorScheme.error,
    };
    final icon = switch (result.status) {
      OpenIrnApiPullStatus.available => Icons.cloud_done_outlined,
      OpenIrnApiPullStatus.empty => Icons.cloud_queue_outlined,
      OpenIrnApiPullStatus.rejected => Icons.lock_outline,
      OpenIrnApiPullStatus.unreachable => Icons.cloud_off_outlined,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 3),
                Text(result.message),
                const SizedBox(height: 3),
                Text('URL : ${result.url}'),
                if (result.statusCode != null)
                  Text('HTTP ${result.statusCode}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteSnapshotList extends StatelessWidget {
  final List<OpenIrnApiPullSnapshot> snapshots;
  final String? importingSnapshotId;
  final ValueChanged<OpenIrnApiPullSnapshot> onImportSnapshot;

  const _RemoteSnapshotList({
    required this.snapshots,
    required this.importingSnapshotId,
    required this.onImportSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Snapshots disponibles',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final snapshot in snapshots) ...[
          _RemoteSnapshotTile(
            snapshot: snapshot,
            importing: importingSnapshotId == snapshot.serverSyncId,
            onImport: () => onImportSnapshot(snapshot),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RemoteSnapshotTile extends StatelessWidget {
  final OpenIrnApiPullSnapshot snapshot;
  final bool importing;
  final VoidCallback onImport;

  const _RemoteSnapshotTile({
    required this.snapshot,
    required this.importing,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final receivedAt = snapshot.receivedAt;
    final payloadAvailable =
        snapshot.payload != null && snapshot.payload!.isNotEmpty;
    final importButton = FilledButton.icon(
      onPressed: importing || !payloadAvailable ? null : onImport,
      icon: importing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_done_outlined),
      label: Text(importing ? 'Import…' : 'Importer'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                snapshot.serverSyncId,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    label: Text(
                      'Appareil : ${snapshot.deviceId.isEmpty ? 'inconnu' : snapshot.deviceId}',
                    ),
                  ),
                  Chip(label: Text('Campagnes : ${snapshot.campaignCount}')),
                  if (receivedAt != null)
                    Chip(label: Text('Reçu : ${receivedAt.toLocal()}')),
                  if (snapshot.payloadSha256.isNotEmpty)
                    Chip(label: Text('SHA-256 : ${snapshot.payloadSha256}')),
                ],
              ),
              if (compact) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: importButton),
              ],
            ],
          );

          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 10),
                Expanded(child: details),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storage_outlined),
              const SizedBox(width: 10),
              Expanded(child: details),
              const SizedBox(width: 8),
              importButton,
            ],
          );
        },
      ),
    );
  }
}

class _ImportResultNotice extends StatelessWidget {
  final SyncPullImportResult result;

  const _ImportResultNotice({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.download_done_outlined, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Snapshot importé sur ce terminal',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(height: 3),
                Text(
                  '${result.campaignCount} campagne(s), ${result.answerCount} réponse(s), '
                  '${result.assignmentCount} affectation(s), ${result.activityEventCount} évènement(s).',
                ),
                if (result.warnings.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${result.warnings.length} avertissement(s) pendant l’import.',
                  ),
                  const SizedBox(height: 4),
                  for (final warning in result.warnings.take(5))
                    Text('• $warning'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteSnapshotPreview extends StatelessWidget {
  final OpenIrnApiPullResult result;

  const _RemoteSnapshotPreview({required this.result});

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    final body = result.responseBody == null
        ? '{}'
        : encoder.convert(result.responseBody);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          body,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text('Impossible de charger la synchronisation : $error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
