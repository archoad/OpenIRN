import 'package:flutter/material.dart';

import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';
import 'assessment_screen.dart';

class EvaluatorAssessmentWorkspaceScreen extends StatefulWidget {
  final IrnReferential referential;
  final AppUser activeUser;
  final LocalCampaignRepository campaignRepository;

  const EvaluatorAssessmentWorkspaceScreen({
    required this.referential,
    required this.activeUser,
    this.campaignRepository = const LocalCampaignRepository(),
    super.key,
  });

  @override
  State<EvaluatorAssessmentWorkspaceScreen> createState() =>
      _EvaluatorAssessmentWorkspaceScreenState();
}

class _EvaluatorAssessmentWorkspaceScreenState
    extends State<EvaluatorAssessmentWorkspaceScreen> {
  final _appSyncCoordinator = AppSyncCoordinator.instance;

  List<EvaluatorCampaignEntry> _campaigns = const [];
  String? _selectedCampaignId;
  String? _selectedAssetId;
  Object? _loadError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  Future<void>? _refreshInFlight;
  int _lastAppliedSyncSerial = 0;

  @override
  void initState() {
    super.initState();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
    _refresh();
  }

  @override
  void dispose() {
    _appSyncCoordinator.removeListener(_handleBackgroundSyncUpdate);
    super.dispose();
  }

  void _handleBackgroundSyncUpdate() {
    final serial = _appSyncCoordinator.changeSerial;
    if (!mounted || serial == _lastAppliedSyncSerial) {
      return;
    }
    _lastAppliedSyncSerial = serial;
    _refresh();
  }

  Future<void> _refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> refresh;
    refresh = _performRefresh().whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<void> _performRefresh() async {
    if (mounted) {
      setState(() {
        _isLoading = _campaigns.isEmpty;
        _isRefreshing = _campaigns.isNotEmpty;
        _loadError = null;
      });
    }

    try {
      final data = await widget.campaignRepository.loadCampaignData(
        referentialId: widget.referential.id,
      );
      final campaigns = evaluatorAssessmentCampaigns(
        data,
        evaluatorId: widget.activeUser.id,
      );
      if (!mounted) {
        return;
      }

      final selectedCampaign = campaigns.where(
        (entry) => entry.campaign.id == _selectedCampaignId,
      );
      final nextCampaign = selectedCampaign.isEmpty
          ? (campaigns.isEmpty ? null : campaigns.first)
          : selectedCampaign.first;
      final selectedAssetExists =
          nextCampaign?.campaign.information.assets.any(
            (asset) => asset.id == _selectedAssetId,
          ) ??
          false;
      final nextAssetId = selectedAssetExists
          ? _selectedAssetId
          : (nextCampaign?.campaign.information.assets.isEmpty ?? true)
          ? null
          : nextCampaign!.campaign.information.assets.first.id;

      setState(() {
        _campaigns = campaigns;
        _selectedCampaignId = nextCampaign?.campaign.id;
        _selectedAssetId = nextAssetId;
        _loadError = null;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _select(EvaluatorCampaignEntry entry, String? assetId) {
    setState(() {
      _selectedCampaignId = entry.campaign.id;
      _selectedAssetId = assetId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: OpenIrnAppBar(title: 'Évaluation IRN'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_campaigns.isEmpty) {
      return Scaffold(
        appBar: const OpenIrnAppBar(title: 'Évaluation IRN'),
        body: _EvaluatorWorkspaceEmptyState(
          error: _loadError,
          onRetry: _refresh,
        ),
      );
    }

    final selected = _campaigns.firstWhere(
      (entry) => entry.campaign.id == _selectedCampaignId,
      orElse: () => _campaigns.first,
    );
    final navigationPanel = _EvaluatorNavigationPanel(
      campaigns: _campaigns,
      selectedCampaignId: selected.campaign.id,
      selectedAssetId: _selectedAssetId,
      isRefreshing: _isRefreshing,
      loadError: _loadError,
      onRetry: _refresh,
      onSelected: _select,
    );

    return AssessmentScreen(
      key: ValueKey<String>(
        'evaluator-assessment-${selected.campaign.id}-${_selectedAssetId ?? 'global'}',
      ),
      referential: widget.referential,
      campaign: selected.campaign,
      activeUser: widget.activeUser,
      initialAssetId: _selectedAssetId,
      showAssetScope: false,
      navigationPanel: navigationPanel,
    );
  }
}

List<EvaluatorCampaignEntry> evaluatorAssessmentCampaigns(
  List<LocalCampaignData> data, {
  required String evaluatorId,
}) {
  final cleanEvaluatorId = evaluatorId.trim();
  if (cleanEvaluatorId.isEmpty) {
    return const [];
  }

  return data
      .where((item) => !item.campaign.isReadOnly)
      .map((item) {
        final assignmentCount = item.assignments
            .where((assignment) => assignment.userId == cleanEvaluatorId)
            .length;
        return EvaluatorCampaignEntry(
          campaign: item.campaign,
          assignmentCount: assignmentCount,
        );
      })
      .where((entry) => entry.assignmentCount > 0)
      .toList(growable: false);
}

class EvaluatorCampaignEntry {
  final LocalCampaign campaign;
  final int assignmentCount;

  const EvaluatorCampaignEntry({
    required this.campaign,
    required this.assignmentCount,
  });
}

class _EvaluatorNavigationPanel extends StatelessWidget {
  final List<EvaluatorCampaignEntry> campaigns;
  final String selectedCampaignId;
  final String? selectedAssetId;
  final bool isRefreshing;
  final Object? loadError;
  final Future<void> Function() onRetry;
  final void Function(EvaluatorCampaignEntry entry, String? assetId) onSelected;

  const _EvaluatorNavigationPanel({
    required this.campaigns,
    required this.selectedCampaignId,
    required this.selectedAssetId,
    required this.isRefreshing,
    required this.loadError,
    required this.onRetry,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey<String>('evaluator-assessment-navigation'),
      color: colors.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isRefreshing) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    'assessment.evaluator_workspace.title',
                    fallback: 'Mes évaluations',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'assessment.evaluator_workspace.description',
                    fallback: 'Choisissez un SI puis un actif à évaluer.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr(
                        'assessment.evaluator_workspace.refresh_error',
                        fallback: 'Actualisation impossible.',
                      ),
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('action.retry', fallback: 'Réessayer'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: campaigns.length,
              itemBuilder: (context, index) {
                final entry = campaigns[index];
                final campaign = entry.campaign;
                final isSelectedCampaign = campaign.id == selectedCampaignId;
                final systemName = campaign.information.systemName.trim();
                final assets = campaign.information.assets;
                return Card(
                  key: ValueKey<String>('evaluator-campaign-${campaign.id}'),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: isSelectedCampaign,
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(
                      systemName.isEmpty
                          ? context.tr(
                              'assessment.evaluator_workspace.unnamed_system',
                              fallback: 'SI non renseigné',
                            )
                          : systemName,
                    ),
                    subtitle: Text(
                      context.tr(
                        'assessment.evaluator_workspace.campaign_summary',
                        fallback: '{campaign} · {count} critère(s) affecté(s)',
                        values: {
                          'campaign': campaign.name,
                          'count': entry.assignmentCount,
                        },
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: assets.isEmpty
                        ? [
                            ListTile(
                              key: ValueKey<String>(
                                'evaluator-campaign-global-${campaign.id}',
                              ),
                              selected:
                                  isSelectedCampaign && selectedAssetId == null,
                              leading: const Icon(Icons.fact_check_outlined),
                              title: Text(
                                context.tr(
                                  'assessment.evaluator_workspace.global',
                                  fallback: 'Évaluation globale',
                                ),
                              ),
                              onTap: () => onSelected(entry, null),
                            ),
                          ]
                        : [
                            for (final asset in assets)
                              ListTile(
                                key: ValueKey<String>(
                                  'evaluator-asset-${campaign.id}-${asset.id}',
                                ),
                                selected:
                                    isSelectedCampaign &&
                                    asset.id == selectedAssetId,
                                leading: Icon(
                                  asset.id == selectedAssetId &&
                                          isSelectedCampaign
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                ),
                                title: Text(asset.displayLabel),
                                subtitle: asset.assetType.trim().isEmpty
                                    ? null
                                    : Text(asset.assetType.trim()),
                                trailing: Text(asset.criticalityShortLabel),
                                onTap: () => onSelected(entry, asset.id),
                              ),
                          ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EvaluatorWorkspaceEmptyState extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;

  const _EvaluatorWorkspaceEmptyState({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                error == null
                    ? Icons.assignment_outlined
                    : Icons.cloud_off_outlined,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                error == null
                    ? context.tr(
                        'assessment.evaluator_workspace.empty',
                        fallback:
                            'Aucune campagne en cours ne contient de critères qui vous sont affectés.',
                      )
                    : context.tr(
                        'assessment.evaluator_workspace.load_error',
                        fallback:
                            'Impossible de charger vos évaluations : {error}',
                        values: {'error': error},
                      ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('action.retry', fallback: 'Réessayer')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
