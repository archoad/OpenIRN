import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_asset_inventory.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../../domain/services/sync_automation_service.dart';
import '../../l10n/openirn_localizations.dart';
import '../activity/activity_log_screen.dart';
import '../assignments/criterion_assignment_screen.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';
import 'assessment_export_screen.dart';
import 'assessment_quality_screen.dart';
import 'assessment_summary_screen.dart';
import 'scoring_method_screen.dart';

String _campaignStatusLabel(BuildContext context, LocalCampaignStatus status) {
  return context.tr(
    'campaign.status.${status.jsonValue}',
    fallback: status.label,
  );
}

String _campaignStatusHelper(BuildContext context, LocalCampaignStatus status) {
  return context.tr(
    'campaign.status.${status.jsonValue}.helper',
    fallback: status.helperText,
  );
}

String _roleLabel(BuildContext context, AppUserRole role) {
  return context.tr('role.${role.jsonValue}', fallback: role.label);
}

String _criterionScopeLabel(BuildContext context, CriterionScope scope) {
  return context.tr(
    'assessment.criterion.scope.${scope.jsonValue}',
    fallback: scope.label,
  );
}

String _answerLabel(BuildContext context, IrnAnswer answer) {
  switch (answer) {
    case IrnAnswer.notAnswered:
      return context.tr(
        'assessment.answer.not_answered.short',
        fallback: answer.label,
      );
    case IrnAnswer.notConcerned:
      return context.tr(
        'assessment.answer.not_concerned.short',
        fallback: answer.label,
      );
    case IrnAnswer.nonResilient:
      return context.tr(
        'assessment.answer.non_resilient.short',
        fallback: answer.label,
      );
    case IrnAnswer.intention:
      return context.tr(
        'assessment.answer.intention.short',
        fallback: answer.label,
      );
    case IrnAnswer.medium:
      return context.tr(
        'assessment.answer.medium.short',
        fallback: answer.label,
      );
    case IrnAnswer.result:
      return context.tr(
        'assessment.answer.result.short',
        fallback: answer.label,
      );
  }
}

String _answerHelp(BuildContext context, IrnAnswer answer) {
  switch (answer) {
    case IrnAnswer.notAnswered:
      return context.tr(
        'assessment.answer.not_answered.help',
        fallback: answer.scoringHelp,
      );
    case IrnAnswer.notConcerned:
      return context.tr(
        'assessment.answer.not_concerned.help',
        fallback: answer.scoringHelp,
      );
    case IrnAnswer.nonResilient:
      return context.tr(
        'assessment.answer.non_resilient.help',
        fallback: answer.scoringHelp,
      );
    case IrnAnswer.intention:
      return context.tr(
        'assessment.answer.intention.help',
        fallback: answer.scoringHelp,
      );
    case IrnAnswer.medium:
      return context.tr(
        'assessment.answer.medium.help',
        fallback: answer.scoringHelp,
      );
    case IrnAnswer.result:
      return context.tr(
        'assessment.answer.result.help',
        fallback: answer.scoringHelp,
      );
  }
}

class AssessmentScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final AppUser activeUser;

  const AssessmentScreen({
    required this.referential,
    required this.campaign,
    required this.activeUser,
    super.key,
  });

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final _catalogService = const ReferentialCatalogService();
  final _scoringService = const OfficialRnrScoringService();
  final _accessPolicy = const AccessPolicyService();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _campaignRepository = const LocalCampaignRepository();
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _activityRepository = const LocalActivityRepository();
  final _userRepository = const LocalUserRepository();
  final _assignmentRepository = const LocalCriterionAssignmentRepository();
  final _syncAutomationService = const SyncAutomationService();
  final _appSyncCoordinator = AppSyncCoordinator.instance;
  final Map<String, CriterionAnswer> _criterionAnswers =
      <String, CriterionAnswer>{};
  final Map<String, AppUser> _usersById = <String, AppUser>{};
  final Map<String, CriterionAssignment> _assignmentsByCriterionId =
      <String, CriterionAssignment>{};
  final Set<String> _expandedPillarIds = <String>{};

  late LocalCampaign _campaign;
  String? _selectedAssetId;

  bool _isLoadingAnswers = true;
  bool _isLoadingAssignments = true;
  bool _isSavingAnswers = false;
  String? _localStatusMessage;
  Timer? _autoPushDebounce;
  Timer? _autoPullTimer;
  Timer? _remoteEventReconnectTimer;
  StreamSubscription<dynamic>? _remoteEventSubscription;
  String? _lastRemoteEventServerSyncId;
  bool _autoSyncRunning = false;
  int _lastAppliedSyncSerial = 0;

  List<CampaignInformationAsset> get _scopedAssets =>
      _campaign.information.assets;

  bool get _isAssetScopedCampaign => _campaign.information.isAssetScoped;

  bool get _shouldShowPersistenceCard {
    final status = _localStatusMessage?.trim() ?? '';
    if (_isSavingAnswers) {
      return true;
    }
    if (status.isEmpty) {
      return false;
    }
    return status.startsWith('Erreur') ||
        status.startsWith('Impossible') ||
        status.startsWith('Mode hors ligne') ||
        status.startsWith('Synchronisation automatique publiée') ||
        status.startsWith('La version serveur');
  }

  String? get _activeAssetId {
    if (!_isAssetScopedCampaign) {
      return null;
    }
    final selected = _selectedAssetId?.trim() ?? '';
    if (selected.isNotEmpty &&
        _scopedAssets.any((asset) => asset.id == selected)) {
      return selected;
    }
    return _scopedAssets.isEmpty ? null : _scopedAssets.first.id;
  }

  CampaignInformationAsset? get _activeAsset =>
      _campaign.information.assetById(_activeAssetId);

  String _answerKeyForCriterion(String criterionId) {
    final assetId = _activeAssetId;
    if (!_isAssetScopedCampaign || assetId == null || assetId.isEmpty) {
      return criterionId;
    }
    return 'asset:$assetId:criterion:$criterionId';
  }

  Map<String, CriterionAnswer> get _activeCriterionAnswers {
    if (!_isAssetScopedCampaign) {
      return Map<String, CriterionAnswer>.unmodifiable(_criterionAnswers);
    }
    final assetId = _activeAssetId;
    if (assetId == null || assetId.isEmpty) {
      return const <String, CriterionAnswer>{};
    }
    final prefix = 'asset:$assetId:criterion:';
    final active = <String, CriterionAnswer>{};
    for (final entry in _criterionAnswers.entries) {
      if (!entry.key.startsWith(prefix)) {
        continue;
      }
      final criterionId = entry.key.substring(prefix.length);
      if (criterionId.isEmpty) {
        continue;
      }
      final answer = entry.value;
      active[criterionId] = CriterionAnswer(
        criterionId: criterionId,
        answer: answer.answer,
        justification: answer.justification,
      );
    }
    return active;
  }

  Map<String, IrnAnswer> get _answers => <String, IrnAnswer>{
    for (final entry in _activeCriterionAnswers.entries)
      entry.key: entry.value.answer,
  };

  int get _justificationCount {
    return _activeCriterionAnswers.values
        .where((answer) => answer.justification.trim().isNotEmpty)
        .length;
  }

  int get _globalJustificationCount {
    return _criterionAnswers.values
        .where((answer) => answer.justification.trim().isNotEmpty)
        .length;
  }

  int _answeredCountForAsset(String assetId) {
    final prefix = 'asset:$assetId:criterion:';
    return _criterionAnswers.entries
        .where(
          (entry) =>
              entry.key.startsWith(prefix) && entry.value.answer.isAnswered,
        )
        .length;
  }

  @override
  void initState() {
    super.initState();
    _campaign = widget.campaign;
    _selectedAssetId = _campaign.information.assets.isEmpty
        ? null
        : _campaign.information.assets.first.id;
    _loadLocalAnswers();
    _loadAssignments();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
    _startAutomaticSynchronization();
    _refreshAssetScopeFromInventory();
  }

  void _setPillarExpanded(String pillarId, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedPillarIds.add(pillarId);
      } else {
        _expandedPillarIds.remove(pillarId);
      }
    });
  }

  Future<void> _refreshAssetScopeFromInventory() async {
    if (!_isAssetScopedCampaign) {
      return;
    }
    final systemId = _campaign.information.informationSystemId.trim();
    if (systemId.isEmpty) {
      return;
    }
    try {
      final configuration = await _configurationRepository.loadConfiguration();
      if (!configuration.isConfigured) {
        return;
      }
      final result = await _apiClient.loadAssetInventory(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );
      if (!mounted || !result.isAvailable) {
        return;
      }
      final inventoryAssets = <String, InformationAssetInfo>{
        for (final asset in result.inventory.assetsForSystem(systemId))
          asset.id: asset,
      };
      if (inventoryAssets.isEmpty) {
        return;
      }

      var changed = false;
      final updatedAssets = _campaign.information.assets
          .map((asset) {
            final inventoryAsset = inventoryAssets[asset.id];
            if (inventoryAsset == null) {
              return asset;
            }
            final inventoryCriticality = inventoryAsset.criticality.trim();
            final merged = CampaignInformationAsset(
              id: asset.id,
              name: inventoryAsset.name.trim().isEmpty
                  ? asset.name
                  : inventoryAsset.name.trim(),
              assetType: inventoryAsset.assetType.trim(),
              criticality: inventoryCriticality.isEmpty
                  ? asset.criticality
                  : inventoryCriticality,
              description: inventoryAsset.description.trim(),
            );
            if (merged.name != asset.name ||
                merged.assetType != asset.assetType ||
                merged.criticality != asset.criticality ||
                merged.description != asset.description) {
              changed = true;
            }
            return merged;
          })
          .toList(growable: false);

      if (!changed || !mounted) {
        return;
      }
      setState(() {
        _campaign = _campaign.copyWith(
          information: _campaign.information.copyWith(assets: updatedAssets),
        );
      });
    } catch (_) {
      // L'évaluation reste utilisable avec les métadonnées embarquées dans la campagne.
    }
  }

  @override
  void dispose() {
    _appSyncCoordinator.removeListener(_handleBackgroundSyncUpdate);
    _autoPushDebounce?.cancel();
    _autoPullTimer?.cancel();
    _remoteEventReconnectTimer?.cancel();
    _remoteEventSubscription?.cancel();
    super.dispose();
  }

  void _handleBackgroundSyncUpdate() {
    final serial = _appSyncCoordinator.changeSerial;
    if (!mounted || serial == _lastAppliedSyncSerial) {
      return;
    }
    _lastAppliedSyncSerial = serial;
    _reloadCurrentCampaignAfterBackgroundImport();
  }

  Future<void> _loadLocalAnswers() async {
    try {
      final criterionAnswers = await _assessmentRepository.loadCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _criterionAnswers
          ..clear()
          ..addAll(criterionAnswers);
        _isLoadingAnswers = false;
        _localStatusMessage = criterionAnswers.isEmpty
            ? 'Aucune évaluation enregistrée.'
            : 'Évaluation restaurée (${criterionAnswers.length} critère(s), $_justificationCount justification(s)).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAnswers = false;
        _localStatusMessage = 'Impossible de restaurer l’évaluation : $error';
      });
    }
  }

  Future<void> _loadAssignments() async {
    try {
      final users = await _userRepository.ensureDefaultUsers();
      final assignments = await _assignmentRepository
          .loadAssignmentsByCriterion(
            referentialId: widget.referential.id,
            campaignId: _campaign.id,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _usersById
          ..clear()
          ..addEntries(users.map((user) => MapEntry(user.id, user)));
        _assignmentsByCriterionId
          ..clear()
          ..addAll(assignments);
        _isLoadingAssignments = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAssignments = false;
        _localStatusMessage = 'Impossible de charger les affectations : $error';
      });
    }
  }

  void _startAutomaticSynchronization() {
    _startRealtimeSynchronization();
    // Filet de sécurité : SSE assure le temps réel, ce polling lent reprend la main
    // si le flux réseau est coupé temporairement par iOS/macOS ou le proxy.
    _autoPullTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pullLatestRemoteVersion(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _pullLatestRemoteVersion(),
    );
  }

  void _startRealtimeSynchronization() {
    _remoteEventReconnectTimer?.cancel();
    _remoteEventSubscription?.cancel();
    _remoteEventSubscription = _syncAutomationService
        .watchRemoteEvents()
        .listen(
          (event) {
            final serverSyncId = event.serverSyncId.trim();
            if (serverSyncId.isEmpty ||
                serverSyncId == _lastRemoteEventServerSyncId) {
              return;
            }
            _lastRemoteEventServerSyncId = serverSyncId;
            _pullLatestRemoteVersion();
          },
          onError: (_) {
            _scheduleRealtimeReconnect();
          },
          onDone: _scheduleRealtimeReconnect,
          cancelOnError: false,
        );
  }

  void _scheduleRealtimeReconnect() {
    if (!mounted) {
      return;
    }
    _remoteEventReconnectTimer?.cancel();
    _remoteEventReconnectTimer = Timer(
      const Duration(seconds: 5),
      _startRealtimeSynchronization,
    );
  }

  void _scheduleAutomaticPush() {
    _autoPushDebounce?.cancel();
    _autoPushDebounce = Timer(
      const Duration(seconds: 3),
      () => _pushLocalVersion(),
    );
  }

  Future<void> _pushLocalVersion() async {
    if (_autoSyncRunning) {
      _autoPushDebounce = Timer(
        const Duration(seconds: 2),
        () => _pushLocalVersion(),
      );
      return;
    }
    _autoSyncRunning = true;
    try {
      final result = await _syncAutomationService.pushLocalSnapshot(
        referential: widget.referential,
        activeUser: widget.activeUser,
      );
      if (!mounted) {
        return;
      }
      if (result.pushedLocalSnapshot) {
        setState(() {
          _localStatusMessage =
              'Synchronisation automatique publiée sur le serveur.';
        });
      } else if (result.outcome == SyncAutomationOutcome.offline ||
          result.outcome == SyncAutomationOutcome.failed) {
        setState(() {
          _localStatusMessage =
              'Synchronisation automatique différée : ${result.title}';
        });
      }
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<void> _pullLatestRemoteVersion() async {
    if (_autoSyncRunning) {
      return;
    }
    _autoSyncRunning = true;
    try {
      final result = await _syncAutomationService.pullLatestIfRemoteNewer(
        referential: widget.referential,
      );
      if (!mounted) {
        return;
      }
      if (result.importedRemoteSnapshot) {
        await _reloadCurrentCampaignAfterAutomaticImport(result);
      } else if (result.outcome == SyncAutomationOutcome.offline ||
          result.outcome == SyncAutomationOutcome.failed) {
        setState(() {
          _localStatusMessage = 'Mode hors ligne temporaire : ${result.title}';
        });
      }
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<void> _reloadCurrentCampaignAfterAutomaticImport(
    SyncAutomationResult result,
  ) async {
    final campaigns = await _campaignRepository.loadCampaigns(
      referentialId: widget.referential.id,
    );
    LocalCampaign? currentCampaign;
    for (final campaign in campaigns) {
      if (campaign.id == _campaign.id) {
        currentCampaign = campaign;
        break;
      }
    }
    currentCampaign ??= campaigns.isEmpty ? null : campaigns.first;

    if (!mounted || currentCampaign == null) {
      return;
    }

    setState(() {
      _campaign = currentCampaign!;
      _isLoadingAnswers = true;
      _isLoadingAssignments = true;
      _localStatusMessage = result.message;
    });
    await _loadLocalAnswers();
    await _loadAssignments();
  }

  Future<void> _reloadCurrentCampaignAfterBackgroundImport() async {
    final campaigns = await _campaignRepository.loadCampaigns(
      referentialId: widget.referential.id,
    );
    LocalCampaign? currentCampaign;
    for (final campaign in campaigns) {
      if (campaign.id == _campaign.id) {
        currentCampaign = campaign;
        break;
      }
    }
    currentCampaign ??= campaigns.isEmpty ? null : campaigns.first;

    if (!mounted || currentCampaign == null) {
      return;
    }

    setState(() {
      _campaign = currentCampaign!;
      _isLoadingAnswers = true;
      _isLoadingAssignments = true;
      _localStatusMessage = _appSyncCoordinator.message;
    });
    await _loadLocalAnswers();
    await _loadAssignments();
  }

  Future<void> _openAssignments() async {
    if (!_accessPolicy.canManageAssignments(widget.activeUser, _campaign)) {
      _showForbidden('Votre rôle ne permet pas de modifier les affectations.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CriterionAssignmentScreen(
          referential: widget.referential,
          campaign: _campaign,
        ),
      ),
    );
    await _loadAssignments();
    _scheduleAutomaticPush();
  }

  Future<void> _setAnswer(IrnCriterion criterion, IrnAnswer answer) async {
    if (!_canEvaluateCriterion(criterion)) {
      _showForbidden(_disabledReasonForCriterion(criterion));
      return;
    }
    final previousAnswers = Map<String, CriterionAnswer>.of(_criterionAnswers);
    final storageKey = _answerKeyForCriterion(criterion.id);
    final current =
        _criterionAnswers[storageKey] ??
        CriterionAnswer(criterionId: storageKey, answer: IrnAnswer.notAnswered);
    final previousAnswer = current.answer;
    final updated = current.copyWith(
      answer: answer,
      justification: answer == IrnAnswer.notAnswered
          ? ''
          : current.justification,
    );

    setState(() {
      _upsertCriterionAnswer(updated);
      _isSavingAnswers = true;
      _localStatusMessage = 'Sauvegarde en cours…';
    });

    final saved = await _saveOrRollback(previousAnswers);
    if (saved && previousAnswer != answer) {
      await _recordActivity(
        type: LocalActivityType.answerChanged,
        title: 'Réponse modifiée',
        description: _activeAsset == null
            ? '${criterion.code} — ${criterion.label}'
            : '${_activeAsset!.displayLabel} · ${criterion.code} — ${criterion.label}',
        criterionId: criterion.id,
        fromValue: previousAnswer.label,
        toValue: answer.label,
      );
    }
  }

  Future<void> _setJustification(
    IrnCriterion criterion,
    String justification,
  ) async {
    if (!_canEvaluateCriterion(criterion)) {
      _showForbidden(_disabledReasonForCriterion(criterion));
      return;
    }
    final previousAnswers = Map<String, CriterionAnswer>.of(_criterionAnswers);
    final storageKey = _answerKeyForCriterion(criterion.id);
    final current =
        _criterionAnswers[storageKey] ??
        CriterionAnswer(criterionId: storageKey, answer: IrnAnswer.notAnswered);
    final previousJustification = current.justification.trim();
    final updatedJustification = justification.trim();
    final updated = current.copyWith(justification: updatedJustification);

    setState(() {
      _upsertCriterionAnswer(updated);
      _isSavingAnswers = true;
      _localStatusMessage = 'Sauvegarde de la justification en cours…';
    });

    final saved = await _saveOrRollback(previousAnswers);
    if (saved && previousJustification != updatedJustification) {
      await _recordActivity(
        type: LocalActivityType.justificationChanged,
        title: updatedJustification.isEmpty
            ? 'Justification supprimée'
            : 'Justification modifiée',
        description: _activeAsset == null
            ? '${criterion.code} — ${criterion.label}'
            : '${_activeAsset!.displayLabel} · ${criterion.code} — ${criterion.label}',
        criterionId: criterion.id,
        fromValue: previousJustification.isEmpty ? 'vide' : 'renseignée',
        toValue: updatedJustification.isEmpty ? 'vide' : 'renseignée',
      );
    }
  }

  void _upsertCriterionAnswer(CriterionAnswer answer) {
    final hasUsefulContent =
        answer.answer != IrnAnswer.notAnswered ||
        answer.justification.trim().isNotEmpty;
    if (!hasUsefulContent) {
      _criterionAnswers.remove(answer.criterionId);
      return;
    }
    _criterionAnswers[answer.criterionId] = answer;
  }

  Future<bool> _saveOrRollback(
    Map<String, CriterionAnswer> previousAnswers,
  ) async {
    try {
      await _assessmentRepository.saveCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
        answers: _criterionAnswers,
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _isSavingAnswers = false;
        final asset = _activeAsset;
        _localStatusMessage = asset == null
            ? 'Évaluation sauvegardée localement ($_justificationCount justification(s)).'
            : 'Évaluation de l’actif « ${asset.displayLabel} » sauvegardée ($_justificationCount justification(s)).';
      });
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _criterionAnswers
          ..clear()
          ..addAll(previousAnswers);
        _isSavingAnswers = false;
        _localStatusMessage = 'Erreur de sauvegarde : $error';
      });
      return false;
    }
  }

  Future<bool> _confirmResetAnswers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(dialogContext),
        title: Text(context.tr('assessment.reset.title')),
        content: ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(context.tr('assessment.reset.body')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('common.action.cancel')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: Text(context.tr('assessment.action.reset')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _resetAnswers() async {
    if (!_accessPolicy.canResetCampaignAnswers(widget.activeUser, _campaign) ||
        _criterionAnswers.isEmpty) {
      return;
    }

    final confirmed = await _confirmResetAnswers();
    if (!confirmed || !mounted) {
      return;
    }

    final previousAnswers = Map<String, CriterionAnswer>.of(_criterionAnswers);

    setState(() {
      _criterionAnswers.clear();
      _isSavingAnswers = true;
      _localStatusMessage = 'Réinitialisation locale en cours…';
    });

    try {
      await _assessmentRepository.clearAnswers(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingAnswers = false;
        _localStatusMessage = 'Évaluation locale réinitialisée.';
      });
      await _recordActivity(
        type: LocalActivityType.answersReset,
        title: 'Réponses réinitialisées',
        description:
            'Toutes les réponses et justifications locales de la campagne ont été supprimées.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _criterionAnswers
          ..clear()
          ..addAll(previousAnswers);
        _isSavingAnswers = false;
        _localStatusMessage = 'Erreur de réinitialisation locale : $error';
      });
    }
  }

  Future<void> _recordActivity({
    required LocalActivityType type,
    required String title,
    String description = '',
    String? criterionId,
    String? fromValue,
    String? toValue,
  }) async {
    await _activityRepository.appendEvent(
      LocalActivityEvent.create(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
        type: type,
        title: title,
        description: description,
        criterionId: criterionId,
        fromValue: fromValue,
        toValue: toValue,
      ),
    );
    _scheduleAutomaticPush();
  }

  Map<IrnPillar, List<IrnCriterion>> _visibleCriteriaByPillar(
    Map<IrnPillar, List<IrnCriterion>> criteriaByPillar,
  ) {
    if (!_accessPolicy.shouldLimitToAssignedCriteria(widget.activeUser)) {
      return criteriaByPillar;
    }

    final result = <IrnPillar, List<IrnCriterion>>{};
    for (final entry in criteriaByPillar.entries) {
      final visibleCriteria = entry.value
          .where(
            (criterion) => _isCriterionAssignedToActiveEvaluator(criterion),
          )
          .toList(growable: false);
      if (visibleCriteria.isNotEmpty) {
        result[entry.key] = visibleCriteria;
      }
    }
    return result;
  }

  bool _isCriterionAssignedToActiveEvaluator(IrnCriterion criterion) {
    final assignment = _assignmentsByCriterionId[criterion.id];
    return assignment != null && assignment.userId == widget.activeUser.id;
  }

  bool _canEvaluateCriterion(IrnCriterion criterion) {
    return _accessPolicy.canEvaluateCriterion(
      user: widget.activeUser,
      campaign: _campaign,
      criterion: criterion,
      assignment: _assignmentsByCriterionId[criterion.id],
    );
  }

  String _disabledReasonForCriterion(IrnCriterion criterion) {
    if (_campaign.isReadOnly) {
      return 'La campagne est en lecture seule.';
    }
    if (!widget.activeUser.active) {
      return 'La session active correspond à un utilisateur inactif.';
    }
    if (widget.activeUser.role == AppUserRole.reader) {
      return 'Lecture seule : rôle Lecteur.';
    }
    if (widget.activeUser.role == AppUserRole.reviewer) {
      return 'Lecture seule : rôle Validateur.';
    }
    if (widget.activeUser.role == AppUserRole.evaluator) {
      final assignment = _assignmentsByCriterionId[criterion.id];
      if (assignment == null) {
        return 'Ce critère n’est pas affecté à votre profil évaluateur.';
      }
      if (assignment.userId != widget.activeUser.id) {
        return 'Critère affecté à un autre évaluateur.';
      }
    }
    return 'Modification non autorisée pour la session active.';
  }

  void _showForbidden(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editCampaignInformation() async {
    if (!_accessPolicy.canEditCampaignInformation(
      widget.activeUser,
      _campaign,
    )) {
      _showForbidden(
        _campaign.isReadOnly
            ? 'La campagne est en lecture seule.'
            : 'Seuls les administrateurs et pilotes IRN peuvent modifier les informations de campagne.',
      );
      return;
    }

    final result = await showDialog<_CampaignInformationFormResult>(
      context: context,
      builder: (_) => _CampaignInformationDialog(campaign: _campaign),
    );
    if (result == null) {
      return;
    }

    final updatedCampaign = await _campaignRepository.updateCampaignInformation(
      referentialId: widget.referential.id,
      campaignId: _campaign.id,
      name: result.name,
      description: result.description,
      information: result.information,
    );
    if (updatedCampaign == null) {
      return;
    }

    setState(() {
      _campaign = updatedCampaign;
      _localStatusMessage = 'Informations de campagne sauvegardées.';
    });

    await _recordActivity(
      type: LocalActivityType.campaignInformationUpdated,
      title: 'Informations campagne modifiées',
      description: updatedCampaign.name,
    );
  }

  Future<void> _openSummary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentSummaryScreen(
          referential: widget.referential,
          campaign: _campaign,
          criterionAnswers: Map<String, CriterionAnswer>.unmodifiable(
            _isAssetScopedCampaign
                ? _criterionAnswers
                : _activeCriterionAnswers,
          ),
        ),
      ),
    );
  }

  Future<void> _openExport() async {
    if (!_accessPolicy.canExportCampaign(widget.activeUser)) {
      _showForbidden('Votre profil ne permet pas d’exporter cette campagne.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentExportScreen(
          referential: widget.referential,
          campaign: _campaign,
          criterionAnswers: Map<String, CriterionAnswer>.unmodifiable(
            _isAssetScopedCampaign
                ? _criterionAnswers
                : _activeCriterionAnswers,
          ),
        ),
      ),
    );
  }

  Future<void> _openScoringMethod() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScoringMethodScreen()),
    );
  }

  Future<void> _openQuality() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentQualityScreen(
          referential: widget.referential,
          campaign: _campaign,
          criterionAnswers: Map<String, CriterionAnswer>.unmodifiable(
            _activeCriterionAnswers,
          ),
        ),
      ),
    );
  }

  Future<void> _openActivityLog() async {
    if (!_accessPolicy.canViewCampaignActivityLog(widget.activeUser)) {
      _showForbidden(
        'Votre profil ne permet pas de consulter le journal de campagne.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityLogScreen(
          referential: widget.referential,
          campaign: _campaign,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCriterionAnswers = _activeCriterionAnswers;
    final answers = _answers;
    final canEditCampaign = _accessPolicy.canEditCampaignInformation(
      widget.activeUser,
      _campaign,
    );
    final canExportCampaign = _accessPolicy.canExportCampaign(
      widget.activeUser,
    );
    final canViewActivityLog = _accessPolicy.canViewCampaignActivityLog(
      widget.activeUser,
    );
    final canResetAnswers = _accessPolicy.canResetCampaignAnswers(
      widget.activeUser,
      _campaign,
    );
    final canManageAssignments = _accessPolicy.canManageAssignments(
      widget.activeUser,
      _campaign,
    );
    final maturitySummary = _isAssetScopedCampaign
        ? _scoringService.computeSystemMaturity(
            widget.referential,
            _campaign,
            _criterionAnswers,
          )
        : null;
    final summary =
        maturitySummary?.aggregateSummary ??
        _scoringService.computeSummary(widget.referential, answers);
    final criteriaByPillar = _catalogService.criteriaByPillar(
      widget.referential,
    );
    final visibleCriteriaByPillar = _visibleCriteriaByPillar(criteriaByPillar);
    final visibleCriteriaCount = visibleCriteriaByPillar.values.fold<int>(
      0,
      (total, criteria) => total + criteria.length,
    );

    return Scaffold(
      appBar: OpenIrnAppBar(
        title: _campaign.name,
        actions: [
          if (canEditCampaign)
            OpenIrnAppBarAction(
              id: 'info',
              label: context.tr('assessment.action.information'),
              icon: Icons.edit_note_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _editCampaignInformation,
            ),
          if (canManageAssignments)
            OpenIrnAppBarAction(
              id: 'assign',
              label: context.tr('assessment.action.assignments'),
              icon: Icons.assignment_ind_outlined,
              enabled: !_isLoadingAnswers && !_isLoadingAssignments,
              onSelected: _openAssignments,
            ),
          OpenIrnAppBarAction(
            id: 'summary',
            label: context.tr('assessment.action.summary'),
            icon: Icons.insights_outlined,
            enabled: !_isLoadingAnswers,
            onSelected: _openSummary,
          ),
          OpenIrnAppBarAction(
            id: 'scoring-method',
            label: context.tr('assessment.action.scoring_method'),
            icon: Icons.functions_outlined,
            enabled: !_isLoadingAnswers,
            onSelected: _openScoringMethod,
          ),
          if (canExportCampaign)
            OpenIrnAppBarAction(
              id: 'export',
              label: context.tr('assessment.action.export_json'),
              icon: Icons.data_object_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _openExport,
            ),
          OpenIrnAppBarAction(
            id: 'quality',
            label: context.tr('assessment.action.quality'),
            icon: Icons.rule_folder_outlined,
            enabled: !_isLoadingAnswers,
            onSelected: _openQuality,
          ),
          if (canViewActivityLog)
            OpenIrnAppBarAction(
              id: 'journal',
              label: context.tr('assessment.action.activity_log'),
              icon: Icons.history_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _openActivityLog,
            ),

          if (canResetAnswers) const OpenIrnAppBarAction.divider(),
          if (canResetAnswers)
            OpenIrnAppBarAction(
              id: 'reset',
              label: context.tr('assessment.action.reset'),
              icon: Icons.refresh,
              enabled:
                  canEditCampaign &&
                  _criterionAnswers.isNotEmpty &&
                  !_isLoadingAnswers &&
                  !_isSavingAnswers,
              destructive: true,
              onSelected: _resetAnswers,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CampaignContextCard(
                referential: widget.referential,
                campaign: _campaign,
                activeUser: widget.activeUser,
                canEdit: canEditCampaign,
                onEditInformation: _editCampaignInformation,
              ),
              const SizedBox(height: 12),
              _AssignmentStatusCard(
                isLoading: _isLoadingAssignments,
                assignmentCount: _assignmentsByCriterionId.length,
                totalCriteria:
                    _accessPolicy.shouldLimitToAssignedCriteria(
                      widget.activeUser,
                    )
                    ? visibleCriteriaCount
                    : widget.referential.criteria
                          .where((criterion) => criterion.active)
                          .length,
                onOpenAssignments: canManageAssignments
                    ? _openAssignments
                    : null,
              ),
              const SizedBox(height: 12),
              _ScoreCard(
                summary: summary,
                maturitySummary: maturitySummary,
                justificationCount: _isAssetScopedCampaign
                    ? _globalJustificationCount
                    : _justificationCount,
              ),
              const SizedBox(height: 12),
              if (_isAssetScopedCampaign) ...[
                _AssetScopeCard(
                  assets: _scopedAssets,
                  selectedAssetId: _activeAssetId,
                  answeredCountForAsset: _answeredCountForAsset,
                  totalCriteria: widget.referential.criteria
                      .where((criterion) => criterion.active)
                      .length,
                  onSelected: (assetId) {
                    setState(() {
                      _selectedAssetId = assetId;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (_shouldShowPersistenceCard) ...[
                _LocalPersistenceCard(
                  isLoading: _isLoadingAnswers,
                  isSaving: _isSavingAnswers,
                  message: _localStatusMessage,
                ),
                const SizedBox(height: 12),
              ],
              if (_isLoadingAnswers || _isLoadingAssignments)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (visibleCriteriaByPillar.isEmpty)
                const _NoAssignedCriteriaCard()
              else
                for (final entry in visibleCriteriaByPillar.entries)
                  _PillarAssessmentCard(
                    key: PageStorageKey<String>(
                      'assessment-pillar-${entry.key.id}',
                    ),
                    pillar: entry.key,
                    criteria: entry.value,
                    initiallyExpanded: _expandedPillarIds.contains(
                      entry.key.id,
                    ),
                    onExpansionChanged: (isExpanded) =>
                        _setPillarExpanded(entry.key.id, isExpanded),
                    criterionAnswers: activeCriterionAnswers,
                    assignmentsByCriterionId: _assignmentsByCriterionId,
                    usersById: _usersById,
                    answers: answers,
                    summary: _scoringService.computeSummaryForPillar(
                      widget.referential,
                      entry.key.id,
                      answers,
                    ),
                    canEditCriterion: _canEvaluateCriterion,
                    disabledReasonForCriterion: _disabledReasonForCriterion,
                    onAnswerChanged: _setAnswer,
                    onJustificationChanged: _setJustification,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoAssignedCriteriaCard extends StatelessWidget {
  const _NoAssignedCriteriaCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.assignment_late_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('assessment.no_assigned.title'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(context.tr('assessment.no_assigned.body')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignContextCard extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final AppUser activeUser;
  final bool canEdit;
  final VoidCallback onEditInformation;

  const _CampaignContextCard({
    required this.referential,
    required this.campaign,
    required this.activeUser,
    required this.canEdit,
    required this.onEditInformation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.folder_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(campaign.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'assessment.context.referential_version',
                      values: {'version': referential.version},
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          _campaignStatusLabel(context, campaign.status),
                        ),
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                        ),
                        label: Text(
                          context.tr(
                            'assessment.context.session',
                            values: {'name': activeUser.displayName},
                          ),
                        ),
                      ),
                      Chip(label: Text(_roleLabel(context, activeUser.role))),
                      if (campaign.isReadOnly)
                        Chip(
                          avatar: const Icon(Icons.lock_outline, size: 18),
                          label: Text(
                            context.tr('assessment.context.read_only'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _campaignStatusHelper(context, campaign.status),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (campaign.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(campaign.description),
                  ],
                  const SizedBox(height: 10),
                  _CampaignInfoRows(campaign: campaign),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: canEdit ? onEditInformation : null,
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(
                        context.tr('assessment.context.edit_information'),
                      ),
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

class _CampaignInfoRows extends StatelessWidget {
  final LocalCampaign campaign;

  const _CampaignInfoRows({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final info = campaign.information;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.dns_outlined, size: 18),
          label: Text(
            info.systemName.trim().isEmpty
                ? context.tr('assessment.context.system_missing')
                : context.tr(
                    'assessment.context.system',
                    values: {'name': info.systemName},
                  ),
          ),
        ),
        if (info.criticalFunctionName.trim().isNotEmpty)
          Chip(
            avatar: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text(
              context.tr(
                'assessment.context.critical_function',
                values: {'name': info.criticalFunctionName},
              ),
            ),
          ),
        if (info.isAssetScoped)
          Chip(
            avatar: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text(
              context.tr(
                'assessment.context.assets_to_score',
                values: {'count': info.assets.length},
              ),
            ),
          ),
        Chip(
          avatar: const Icon(Icons.person_outline, size: 18),
          label: Text(_projectDirectorLabel(context, info)),
        ),
      ],
    );
  }

  String _projectDirectorLabel(BuildContext context, CampaignInformation info) {
    final name = info.projectDirectorFullName;
    final email = info.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return context.tr(
        'assessment.context.project_director_name_email',
        values: {'name': name, 'email': email},
      );
    }
    if (name.isNotEmpty) {
      return context.tr(
        'assessment.context.project_director_name',
        values: {'name': name},
      );
    }
    if (email.isNotEmpty) {
      return context.tr(
        'assessment.context.project_director_email',
        values: {'email': email},
      );
    }
    return context.tr('assessment.context.project_director_missing');
  }
}

class _CampaignInformationFormResult {
  final String name;
  final String description;
  final CampaignInformation information;

  const _CampaignInformationFormResult({
    required this.name,
    required this.description,
    required this.information,
  });
}

class _CampaignInformationDialog extends StatefulWidget {
  final LocalCampaign campaign;

  const _CampaignInformationDialog({required this.campaign});

  @override
  State<_CampaignInformationDialog> createState() =>
      _CampaignInformationDialogState();
}

class _CampaignInformationDialogState
    extends State<_CampaignInformationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _systemNameController;
  late final TextEditingController _systemDescriptionController;
  late final TextEditingController _projectDirectorFirstNameController;
  late final TextEditingController _projectDirectorLastNameController;
  late final TextEditingController _projectDirectorEmailController;

  @override
  void initState() {
    super.initState();
    final campaign = widget.campaign;
    final info = campaign.information;
    _nameController = TextEditingController(text: campaign.name);
    _descriptionController = TextEditingController(text: campaign.description);
    _systemNameController = TextEditingController(text: info.systemName);
    _systemDescriptionController = TextEditingController(
      text: info.systemDescription,
    );
    _projectDirectorFirstNameController = TextEditingController(
      text: info.projectDirectorFirstName,
    );
    _projectDirectorLastNameController = TextEditingController(
      text: info.projectDirectorLastName,
    );
    _projectDirectorEmailController = TextEditingController(
      text: info.projectDirectorEmail,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _systemNameController.dispose();
    _systemDescriptionController.dispose();
    _projectDirectorFirstNameController.dispose();
    _projectDirectorLastNameController.dispose();
    _projectDirectorEmailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(
      _CampaignInformationFormResult(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        information: widget.campaign.information.copyWith(
          systemName: _systemNameController.text.trim(),
          systemDescription: _systemDescriptionController.text.trim(),
          projectDirectorFirstName: _projectDirectorFirstNameController.text
              .trim(),
          projectDirectorLastName: _projectDirectorLastNameController.text
              .trim(),
          projectDirectorEmail: _projectDirectorEmailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(context.tr('assessment.information.title')),
      content: ResponsiveDialogContent(
        maxWidth: 880,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('assessment.information.section.campaign'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameController,
                  autofocus: shouldAutofocusTextField(context),
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'assessment.information.campaign_name',
                    ),
                    hintText: context.tr(
                      'assessment.information.campaign_name_hint',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? context.tr(
                          'assessment.validation.campaign_name_required',
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'assessment.information.campaign_description',
                    ),
                    hintText: context.tr(
                      'assessment.information.campaign_description_hint',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.tr(
                    'assessment.information.section.information_system',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _systemNameController,
                  decoration: InputDecoration(
                    labelText: context.tr('assessment.information.system_name'),
                    hintText: context.tr(
                      'assessment.information.system_name_hint',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? context.tr('assessment.validation.system_name_required')
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _systemDescriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'assessment.information.system_description',
                    ),
                    hintText: context.tr(
                      'assessment.information.system_description_hint',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? context.tr(
                          'assessment.validation.system_description_required',
                        )
                      : null,
                ),
                const SizedBox(height: 18),
                Text(
                  context.tr('assessment.information.section.project_director'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _projectDirectorFirstNameController,
                        decoration: InputDecoration(
                          labelText: context.tr(
                            'assessment.information.first_name',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.tr(
                                'assessment.validation.first_name_required',
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _projectDirectorLastNameController,
                        decoration: InputDecoration(
                          labelText: context.tr(
                            'assessment.information.last_name',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.tr(
                                'assessment.validation.last_name_required',
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _projectDirectorEmailController,
                  keyboardType: safeKeyboardType(
                    context,
                    TextInputType.emailAddress,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: context.tr('assessment.information.email'),
                    hintText: context.tr('assessment.information.email_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return context.tr('assessment.validation.email_required');
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return context.tr('assessment.validation.email_invalid');
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.tr('common.action.save')),
        ),
      ],
    );
  }
}

class _AssignmentStatusCard extends StatelessWidget {
  final bool isLoading;
  final int assignmentCount;
  final int totalCriteria;
  final VoidCallback? onOpenAssignments;

  const _AssignmentStatusCard({
    required this.isLoading,
    required this.assignmentCount,
    required this.totalCriteria,
    required this.onOpenAssignments,
  });

  @override
  Widget build(BuildContext context) {
    final label = isLoading
        ? context.tr('assessment.assignments.loading')
        : context.tr(
            'assessment.assignments.count',
            values: {'assigned': assignmentCount, 'total': totalCriteria},
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.assignment_ind_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            TextButton.icon(
              onPressed: isLoading ? null : onOpenAssignments,
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.tr('assessment.assignments.manage')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentChip extends StatelessWidget {
  final CriterionAssignment? assignment;
  final AppUser? assignedUser;

  const _AssignmentChip({required this.assignment, required this.assignedUser});

  String _assignedUserLabel(BuildContext context) {
    final user = assignedUser;
    if (user != null) {
      final fullName = user.fullName.trim();
      if (fullName.isNotEmpty) {
        return fullName;
      }
      final email = user.email.trim();
      if (email.isNotEmpty) {
        return email;
      }
    }
    return context.tr('assessment.assignment.user_unresolved');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssigned = assignment != null;
    final label = isAssigned
        ? context.tr(
            'assessment.assignment.evaluator',
            values: {'user': _assignedUserLabel(context)},
          )
        : context.tr('assessment.assignment.unassigned');
    final icon = isAssigned ? Icons.person_outline : Icons.person_off_outlined;
    final backgroundColor = isAssigned
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    return Tooltip(
      message: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final IrnScoreSummary summary;
  final IrnSystemMaturitySummary? maturitySummary;
  final int justificationCount;

  const _ScoreCard({
    required this.summary,
    required this.maturitySummary,
    required this.justificationCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maturity = maturitySummary;
    final score = maturity?.maturityScore ?? summary.openIrnRnrScore;
    final formattedScore =
        maturity?.formattedMaturityScore ?? summary.formattedOpenIrnRnrScore;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('assessment.score.title'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        maturity == null
                            ? context.tr(
                                'assessment.score.standard_description',
                              )
                            : context.tr(
                                'assessment.score.si_maturity_description',
                              ),
                      ),
                    ],
                  ),
                ),
                Text(formattedScore, style: theme.textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: score == null ? 0 : score / 100),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.criteria',
                      values: {'count': summary.totalCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.answered',
                      values: {'count': summary.answeredCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.not_concerned',
                      values: {'count': summary.notConcernedCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.non_resilient',
                      values: {'count': summary.nonResilientCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.intention',
                      values: {'count': summary.intentionCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.medium',
                      values: {'count': summary.mediumCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.result',
                      values: {'count': summary.resultCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.not_answered',
                      values: {'count': summary.notAnsweredCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.justifications',
                      values: {'count': justificationCount},
                    ),
                  ),
                ),
                if (maturity != null) ...[
                  Chip(
                    label: Text(
                      context.tr(
                        'assessment.score.scored_assets',
                        values: {
                          'scored': maturity.scoredAssetCount,
                          'total': maturity.totalAssetCount,
                        },
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'assessment.score.criticality_weight',
                        values: {'weight': maturity.maturityWeightTotal},
                      ),
                    ),
                  ),
                ],
                Chip(
                  label: Text(
                    context.tr(
                      'assessment.score.completion',
                      values: {
                        'rate': (summary.completionRate * 100).toStringAsFixed(
                          0,
                        ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalPersistenceCard extends StatelessWidget {
  final bool isLoading;
  final bool isSaving;
  final String? message;

  const _LocalPersistenceCard({
    required this.isLoading,
    required this.isSaving,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = isLoading || isSaving ? Icons.sync : Icons.save_outlined;
    final label = message == null
        ? context.tr('assessment.persistence.ready')
        : context.trText(message!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            if (isLoading || isSaving)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssetScopeCard extends StatelessWidget {
  final List<CampaignInformationAsset> assets;
  final String? selectedAssetId;
  final int Function(String assetId) answeredCountForAsset;
  final int totalCriteria;
  final ValueChanged<String> onSelected;

  const _AssetScopeCard({
    required this.assets,
    required this.selectedAssetId,
    required this.answeredCountForAsset,
    required this.totalCriteria,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = selectedAssetId?.trim().isNotEmpty == true
        ? selectedAssetId
        : (assets.isEmpty ? null : assets.first.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('assessment.asset_scope.title'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('assessment.asset_scope.description'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (assets.isEmpty)
              Text(context.tr('assessment.asset_scope.empty'))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final asset in assets)
                    _AssetProgressButton(
                      asset: asset,
                      isSelected: asset.id == selected,
                      answeredCount: answeredCountForAsset(asset.id),
                      totalCriteria: totalCriteria,
                      onTap: () => onSelected(asset.id),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AssetProgressButton extends StatelessWidget {
  final CampaignInformationAsset asset;
  final bool isSelected;
  final int answeredCount;
  final int totalCriteria;
  final VoidCallback onTap;

  const _AssetProgressButton({
    required this.asset,
    required this.isSelected,
    required this.answeredCount,
    required this.totalCriteria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressLabel = totalCriteria <= 0
        ? '$answeredCount'
        : '$answeredCount/$totalCriteria';
    final tooltip = asset.description.trim().isEmpty
        ? context.tr(
            'assessment.asset_scope.tooltip',
            values: {'asset': asset.displayLabel, 'progress': progressLabel},
          )
        : context.tr(
            'assessment.asset_scope.tooltip_with_description',
            values: {
              'asset': asset.displayLabel,
              'progress': progressLabel,
              'description': asset.description.trim(),
            },
          );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: context.tr(
          'assessment.asset_scope.semantic_label',
          values: {
            'asset': asset.displayLabel,
            'criticality': asset.criticalityLabel,
            'progress': progressLabel,
          },
        ),
        child: ChoiceChip(
          selected: isSelected,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            isSelected ? Icons.check_circle : Icons.inventory_2_outlined,
            size: 18,
            color: isSelected ? colorScheme.onPrimaryContainer : null,
          ),
          label: Text(
            '${asset.displayLabel} · ${asset.criticalityShortLabel} · $progressLabel',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PillarAssessmentCard extends StatelessWidget {
  final IrnPillar pillar;
  final List<IrnCriterion> criteria;
  final Map<String, CriterionAnswer> criterionAnswers;
  final Map<String, CriterionAssignment> assignmentsByCriterionId;
  final Map<String, AppUser> usersById;
  final Map<String, IrnAnswer> answers;
  final IrnScoreSummary summary;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final bool Function(IrnCriterion criterion) canEditCriterion;
  final String Function(IrnCriterion criterion) disabledReasonForCriterion;
  final void Function(IrnCriterion criterion, IrnAnswer answer) onAnswerChanged;
  final void Function(IrnCriterion criterion, String justification)
  onJustificationChanged;

  const _PillarAssessmentCard({
    super.key,
    required this.pillar,
    required this.criteria,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    required this.criterionAnswers,
    required this.assignmentsByCriterionId,
    required this.usersById,
    required this.answers,
    required this.summary,
    required this.canEditCriterion,
    required this.disabledReasonForCriterion,
    required this.onAnswerChanged,
    required this.onJustificationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final justificationCount = criteria
        .where(
          (criterion) =>
              criterionAnswers[criterion.id]?.justification.trim().isNotEmpty ??
              false,
        )
        .length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        onExpansionChanged: onExpansionChanged,
        title: Text('${pillar.code} — ${pillar.label}'),
        subtitle: Text(
          context.tr(
            'assessment.pillar.subtitle',
            values: {
              'answered': summary.answeredCriteria,
              'total': summary.totalCriteria,
              'justifications': justificationCount,
              'score': summary.formattedOpenIrnRnrScore,
            },
          ),
        ),
        children: [
          for (final criterion in criteria)
            SizedBox(
              width: double.infinity,
              child: _CriterionAnswerTile(
                criterion: criterion,
                answer: answers[criterion.id] ?? IrnAnswer.notAnswered,
                justification:
                    criterionAnswers[criterion.id]?.justification ?? '',
                assignment: assignmentsByCriterionId[criterion.id],
                assignedUser:
                    usersById[assignmentsByCriterionId[criterion.id]?.userId],
                canEdit: canEditCriterion(criterion),
                disabledReason: disabledReasonForCriterion(criterion),
                onAnswerChanged: (answer) => onAnswerChanged(criterion, answer),
                onJustificationChanged: (justification) =>
                    onJustificationChanged(criterion, justification),
              ),
            ),
        ],
      ),
    );
  }
}

class _CriterionAnswerTile extends StatelessWidget {
  final IrnCriterion criterion;
  final IrnAnswer answer;
  final String justification;
  final CriterionAssignment? assignment;
  final AppUser? assignedUser;
  final bool canEdit;
  final String disabledReason;
  final ValueChanged<IrnAnswer> onAnswerChanged;
  final ValueChanged<String> onJustificationChanged;

  const _CriterionAnswerTile({
    required this.criterion,
    required this.answer,
    required this.justification,
    required this.assignment,
    required this.assignedUser,
    required this.canEdit,
    required this.disabledReason,
    required this.onAnswerChanged,
    required this.onJustificationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasJustification = justification.trim().isNotEmpty;
    final canJustify = answer.isAnswered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${criterion.code} — ${criterion.label}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            'assessment.criterion.scope_label',
                            values: {
                              'scope': _criterionScopeLabel(
                                context,
                                criterion.scope,
                              ),
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        _AssignmentChip(
                          assignment: assignment,
                          assignedUser: assignedUser,
                        ),
                        if (!canEdit) ...[
                          const SizedBox(height: 4),
                          Text(
                            context.trText(disabledReason),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    );
                    final choices = Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final option in IrnAnswer.ratingValues)
                          ChoiceChip(
                            label: Text(_answerLabel(context, option)),
                            tooltip: _answerHelp(context, option),
                            selected: answer == option,
                            onSelected: canEdit
                                ? (_) => onAnswerChanged(option)
                                : null,
                          ),
                      ],
                    );
                    final isNarrow = constraints.maxWidth < 520;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          details,
                          const SizedBox(height: 10),
                          choices,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: details),
                        const SizedBox(width: 12),
                        Flexible(child: choices),
                      ],
                    );
                  },
                ),
                if (canJustify) ...[
                  const SizedBox(height: 8),
                  if (hasJustification)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: Text(
                        justification.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    Text(
                      context.tr('assessment.justification.empty'),
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: canEdit
                          ? () => _openJustificationDialog(context)
                          : null,
                      icon: Icon(
                        hasJustification
                            ? Icons.edit_note
                            : Icons.note_add_outlined,
                      ),
                      label: Text(
                        hasJustification
                            ? context.tr('assessment.justification.edit')
                            : context.tr('assessment.justification.add'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openJustificationDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _JustificationDialog(
        criterionCode: criterion.code,
        initialText: justification,
      ),
    );

    if (result == null) {
      return;
    }
    onJustificationChanged(result);
  }
}

class _JustificationDialog extends StatefulWidget {
  final String criterionCode;
  final String initialText;

  const _JustificationDialog({
    required this.criterionCode,
    required this.initialText,
  });

  @override
  State<_JustificationDialog> createState() => _JustificationDialogState();
}

class _JustificationDialogState extends State<_JustificationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'assessment.justification.dialog_title',
          values: {'criterion': widget.criterionCode},
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 780,
        child: TextField(
          controller: _controller,
          autofocus: shouldAutofocusTextField(context),
          minLines: 5,
          maxLines: 10,
          decoration: InputDecoration(
            labelText: context.tr('assessment.justification.label'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            hintText: context.tr('assessment.justification.hint'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(context.tr('assessment.justification.clear')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.tr('common.action.save')),
        ),
      ],
    );
  }
}
