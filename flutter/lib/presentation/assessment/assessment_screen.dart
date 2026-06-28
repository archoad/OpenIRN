import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../../domain/services/sync_automation_service.dart';
import '../activity/activity_log_screen.dart';
import '../admin/campaign_history_screen.dart';
import '../admin/server_maintenance_screen.dart';
import '../assignments/criterion_assignment_screen.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';
import '../sync/sync_screen.dart';
import 'assessment_export_screen.dart';
import 'assessment_quality_screen.dart';
import 'assessment_summary_screen.dart';

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

  late LocalCampaign _campaign;

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

  Map<String, IrnAnswer> get _answers => <String, IrnAnswer>{
    for (final entry in _criterionAnswers.entries)
      entry.key: entry.value.answer,
  };

  int get _justificationCount {
    return _criterionAnswers.values
        .where((answer) => answer.justification.trim().isNotEmpty)
        .length;
  }

  @override
  void initState() {
    super.initState();
    _campaign = widget.campaign;
    _loadLocalAnswers();
    _loadAssignments();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
    _startAutomaticSynchronization();
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
            ? 'Aucune évaluation enregistrée sur ce terminal.'
            : 'Évaluation restaurée depuis ce terminal (${criterionAnswers.length} critère(s), $_justificationCount justification(s)).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAnswers = false;
        _localStatusMessage =
            'Impossible de restaurer l’évaluation depuis ce terminal : $error';
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
      _showForbidden('Ton rôle ne permet pas de modifier les affectations.');
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
    final current =
        _criterionAnswers[criterion.id] ??
        CriterionAnswer(
          criterionId: criterion.id,
          answer: IrnAnswer.notAnswered,
        );
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
      _localStatusMessage = 'Sauvegarde de ce terminal en cours…';
    });

    final saved = await _saveOrRollback(previousAnswers);
    if (saved && previousAnswer != answer) {
      await _recordActivity(
        type: LocalActivityType.answerChanged,
        title: 'Réponse modifiée',
        description: '${criterion.code} — ${criterion.label}',
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
    final current =
        _criterionAnswers[criterion.id] ??
        CriterionAnswer(
          criterionId: criterion.id,
          answer: IrnAnswer.notAnswered,
        );
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
        description: '${criterion.code} — ${criterion.label}',
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
        _localStatusMessage =
            'Évaluation sauvegardée localement ($_justificationCount justification(s)).';
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
        _localStatusMessage = 'Erreur de sauvegarde de ce terminal : $error';
      });
      return false;
    }
  }

  Future<bool> _confirmResetAnswers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(dialogContext),
        title: const Text('Réinitialiser la campagne ?'),
        content: const ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            'Cette action supprimera toutes les réponses R / NR et toutes les justifications de cette campagne. '
            'Elle ne peut pas être annulée.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _resetAnswers() async {
    if (!_accessPolicy.canManageCampaigns(widget.activeUser) ||
        _campaign.isReadOnly ||
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
    if (widget.activeUser.role != AppUserRole.evaluator) {
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
        return 'Critère non affecté à ton profil évaluateur.';
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
    if (!_accessPolicy.canManageCampaigns(widget.activeUser) ||
        _campaign.isReadOnly) {
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
            _criterionAnswers,
          ),
        ),
      ),
    );
  }

  Future<void> _openExport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentExportScreen(
          referential: widget.referential,
          campaign: _campaign,
          criterionAnswers: Map<String, CriterionAnswer>.unmodifiable(
            _criterionAnswers,
          ),
        ),
      ),
    );
  }

  Future<void> _openQuality() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentQualityScreen(
          referential: widget.referential,
          campaign: _campaign,
          criterionAnswers: Map<String, CriterionAnswer>.unmodifiable(
            _criterionAnswers,
          ),
        ),
      ),
    );
  }

  Future<void> _openCampaignHistory() async {
    if (!_accessPolicy.canManageCampaigns(widget.activeUser)) {
      _showForbidden(
        'Seuls les administrateurs et pilotes IRN peuvent consulter l’historique serveur.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CampaignHistoryScreen(
          activeUser: widget.activeUser,
          initialCampaignId: _campaign.id,
          initialCampaignName: _campaign.name,
        ),
      ),
    );
  }

  Future<void> _openServerMaintenance() async {
    if (!_accessPolicy.canManageCampaigns(widget.activeUser)) {
      _showForbidden(
        'Seuls les administrateurs et pilotes IRN peuvent accéder à la maintenance serveur.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerMaintenanceScreen(activeUser: widget.activeUser),
      ),
    );
  }

  Future<void> _openActivityLog() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityLogScreen(
          referential: widget.referential,
          campaign: _campaign,
        ),
      ),
    );
  }

  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyncScreen(referential: widget.referential),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final answers = _answers;
    final canManageCampaign = _accessPolicy.canManageCampaigns(
      widget.activeUser,
    );
    final canEditCampaign = canManageCampaign && !_campaign.isReadOnly;
    final canManageAssignments = _accessPolicy.canManageAssignments(
      widget.activeUser,
      _campaign,
    );
    final summary = _scoringService.computeSummary(widget.referential, answers);
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
              label: 'Informations',
              icon: Icons.edit_note_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _editCampaignInformation,
            ),
          if (canManageAssignments)
            OpenIrnAppBarAction(
              id: 'assign',
              label: 'Affectations',
              icon: Icons.assignment_ind_outlined,
              enabled: !_isLoadingAnswers && !_isLoadingAssignments,
              onSelected: _openAssignments,
            ),
          OpenIrnAppBarAction(
            id: 'sync',
            label: 'Synchronisation',
            icon: Icons.cloud_sync_outlined,
            enabled: !_isLoadingAnswers,
            onSelected: _openSync,
          ),
          OpenIrnAppBarAction(
            id: 'summary',
            label: 'Synthèse',
            icon: Icons.insights_outlined,
            enabled: !_isLoadingAnswers,
            onSelected: _openSummary,
          ),
          if (canManageCampaign)
            OpenIrnAppBarAction(
              id: 'export',
              label: 'Export JSON',
              icon: Icons.data_object_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _openExport,
            ),
          OpenIrnAppBarAction(
            id: 'quality',
            label: 'Qualité',
            icon: Icons.rule_folder_outlined,
            enabled: !_isLoadingAnswers,
            onSelected: _openQuality,
          ),
          if (canManageCampaign)
            OpenIrnAppBarAction(
              id: 'journal',
              label: 'Journal',
              icon: Icons.history_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _openActivityLog,
            ),

          if (canManageCampaign)
            OpenIrnAppBarAction(
              id: 'history_conflicts',
              label: 'Historique / conflits',
              icon: Icons.manage_history_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _openCampaignHistory,
            ),
          if (canManageCampaign)
            OpenIrnAppBarAction(
              id: 'server_maintenance',
              label: 'Maintenance serveur',
              icon: Icons.admin_panel_settings_outlined,
              enabled: !_isLoadingAnswers,
              onSelected: _openServerMaintenance,
            ),
          if (canManageCampaign) const OpenIrnAppBarAction.divider(),
          if (canManageCampaign)
            OpenIrnAppBarAction(
              id: 'reset',
              label: 'Réinitialiser',
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
                totalCriteria: widget.activeUser.role == AppUserRole.evaluator
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
                justificationCount: _justificationCount,
              ),
              const SizedBox(height: 12),
              _LocalPersistenceCard(
                isLoading: _isLoadingAnswers,
                isSaving: _isSavingAnswers,
                message: _localStatusMessage,
              ),
              const SizedBox(height: 12),
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
                    pillar: entry.key,
                    criteria: entry.value,
                    criterionAnswers: _criterionAnswers,
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
                    'Aucun critère affecté',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ton profil Évaluateur ne possède actuellement aucune affectation sur cette campagne.',
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
                  Text('Campagne · Référentiel ${referential.version}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(campaign.status.label)),
                      Chip(
                        avatar: const Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                        ),
                        label: Text('Session : ${activeUser.displayName}'),
                      ),
                      Chip(label: Text(activeUser.role.label)),
                      if (campaign.isReadOnly)
                        const Chip(
                          avatar: Icon(Icons.lock_outline, size: 18),
                          label: Text('Lecture seule'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    campaign.status.helperText,
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
                      label: const Text(
                        'Modifier les informations de campagne',
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
                ? 'SI non renseigné'
                : 'SI : ${info.systemName}',
          ),
        ),
        Chip(
          avatar: const Icon(Icons.person_outline, size: 18),
          label: Text(_projectDirectorLabel(info)),
        ),
      ],
    );
  }

  String _projectDirectorLabel(CampaignInformation info) {
    final name = info.projectDirectorFullName;
    final email = info.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return 'Directeur : $name <$email>';
    }
    if (name.isNotEmpty) {
      return 'Directeur : $name';
    }
    if (email.isNotEmpty) {
      return 'Directeur : $email';
    }
    return 'Directeur projet non renseigné';
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
        information: CampaignInformation(
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
      title: const Text('Informations de campagne'),
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
                  'Campagne',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameController,
                  autofocus: shouldAutofocusTextField(context),
                  decoration: const InputDecoration(
                    labelText: 'Nom de la campagne',
                    hintText: 'Ex. Évaluation IRN 2026 — SI Facturation',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Le nom de campagne est obligatoire.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description de la campagne',
                    hintText:
                        'Périmètre, contexte ou objectif de l’évaluation.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Système d’information concerné',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _systemNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du système d’information',
                    hintText: 'Ex. SI Facturation',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Le nom du SI est obligatoire.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _systemDescriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Description du système d’information',
                    hintText:
                        'Fonction métier supportée, criticité, principaux composants ou dépendances.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'La description du SI est obligatoire.'
                      : null,
                ),
                const SizedBox(height: 18),
                Text(
                  'Directeur de projet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _projectDirectorFirstNameController,
                        decoration: const InputDecoration(
                          labelText: 'Prénom',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Prénom obligatoire.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _projectDirectorLastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nom',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Nom obligatoire.'
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
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'prenom.nom@entreprise.fr',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Email obligatoire.';
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Email invalide.';
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
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
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
        ? 'Chargement des affectations…'
        : 'Critères affectés : $assignmentCount/$totalCriteria';
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
              label: const Text('Gérer les affectations'),
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

  String get _assignedUserLabel {
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
    final userId = assignment?.userId.trim() ?? '';
    if (userId.isEmpty) {
      return 'Utilisateur inconnu';
    }
    return 'Utilisateur $userId';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssigned = assignment != null;
    final label = isAssigned
        ? 'Évaluateur : $_assignedUserLabel'
        : 'Non affecté';
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
  final int justificationCount;

  const _ScoreCard({required this.summary, required this.justificationCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = summary.officialScore;

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
                        'Score officiel R / NR',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Calcul : R / (R + NR). Les critères non cotés sont exclus du score.',
                      ),
                    ],
                  ),
                ),
                Text(
                  summary.formattedOfficialScore,
                  style: theme.textTheme.headlineMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: score == null ? 0 : score / 100),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Critères : ${summary.totalCriteria}')),
                Chip(label: Text('Cotés : ${summary.answeredCriteria}')),
                Chip(label: Text('R : ${summary.resilientCriteria}')),
                Chip(label: Text('NR : ${summary.nonResilientCriteria}')),
                Chip(label: Text('N.C. : ${summary.notAnsweredCriteria}')),
                Chip(label: Text('Justifications : $justificationCount')),
                Chip(
                  label: Text(
                    'Complétude : ${(summary.completionRate * 100).toStringAsFixed(0)} %',
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
    final label = message ?? 'Sauvegarde prête.';

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

class _PillarAssessmentCard extends StatelessWidget {
  final IrnPillar pillar;
  final List<IrnCriterion> criteria;
  final Map<String, CriterionAnswer> criterionAnswers;
  final Map<String, CriterionAssignment> assignmentsByCriterionId;
  final Map<String, AppUser> usersById;
  final Map<String, IrnAnswer> answers;
  final IrnScoreSummary summary;
  final bool Function(IrnCriterion criterion) canEditCriterion;
  final String Function(IrnCriterion criterion) disabledReasonForCriterion;
  final void Function(IrnCriterion criterion, IrnAnswer answer) onAnswerChanged;
  final void Function(IrnCriterion criterion, String justification)
  onJustificationChanged;

  const _PillarAssessmentCard({
    required this.pillar,
    required this.criteria,
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
        initiallyExpanded: false,
        title: Text('${pillar.code} — ${pillar.label}'),
        subtitle: Text(
          '${summary.answeredCriteria}/${summary.totalCriteria} coté(s) · '
          '$justificationCount justification(s) · Score : ${summary.formattedOfficialScore}',
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
    final canJustify =
        answer == IrnAnswer.resilient || answer == IrnAnswer.nonResilient;

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
                        Text('Portée : ${criterion.scope.label}'),
                        const SizedBox(height: 6),
                        _AssignmentChip(
                          assignment: assignment,
                          assignedUser: assignedUser,
                        ),
                        if (!canEdit) ...[
                          const SizedBox(height: 4),
                          Text(
                            disabledReason,
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
                        for (final option in IrnAnswer.values)
                          ChoiceChip(
                            label: Text(option.label),
                            tooltip: option.longLabel,
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
                      'Aucune justification renseignée.',
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
                            ? 'Modifier la justification'
                            : 'Ajouter une justification',
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
      title: Text('Justification — ${widget.criterionCode}'),
      content: ResponsiveDialogContent(
        maxWidth: 780,
        child: TextField(
          controller: _controller,
          autofocus: shouldAutofocusTextField(context),
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Justification / commentaire',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
            hintText:
                'Explique la réponse, cite une preuve, une hypothèse ou un point à vérifier.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Effacer'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
