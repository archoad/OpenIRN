import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../data/repositories/server_campaign_store.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_asset_inventory.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/sync_automation_service.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class CampaignManagementScreen extends StatefulWidget {
  final IrnReferential referential;
  final AppUser activeUser;

  const CampaignManagementScreen({
    required this.referential,
    required this.activeUser,
    super.key,
  });

  @override
  State<CampaignManagementScreen> createState() =>
      _CampaignManagementScreenState();
}

class _CampaignManagementScreenState extends State<CampaignManagementScreen> {
  final _campaignRepository = const LocalCampaignRepository();
  final _activityRepository = const LocalActivityRepository();
  final _syncAutomationService = const SyncAutomationService();
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _appSyncCoordinator = AppSyncCoordinator.instance;

  late Future<List<LocalCampaign>> _campaignsFuture;
  int _lastAppliedSyncSerial = 0;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _campaignsFuture = _loadCampaigns();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
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

  Future<List<LocalCampaign>> _loadCampaigns() {
    return _campaignRepository.loadCampaigns(
      referentialId: widget.referential.id,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _campaignsFuture = _loadCampaigns();
    });
    await _campaignsFuture;
  }

  Future<IrnAssetInventory?> _loadInventoryForCampaignCreation() async {
    try {
      final configuration = await _configurationRepository.loadConfiguration();
      if (!configuration.isConfigured) {
        return null;
      }
      final result = await _apiClient.loadAssetInventory(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );
      return result.isAvailable ? result.inventory : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _createCampaign() async {
    final inventory = await _loadInventoryForCampaignCreation();
    if (!mounted) {
      return;
    }
    final result = await showDialog<_CampaignFormResult>(
      context: context,
      builder: (_) => _CreateCampaignDialog(inventory: inventory),
    );
    if (!mounted || result == null) {
      return;
    }

    final campaignCreatedTitle = context.tr(
      'screen.campaign.created',
      fallback: 'Campagne créée',
    );

    setState(() {
      _isWorking = true;
    });

    try {
      final campaign = await _campaignRepository.createCampaign(
        referentialId: widget.referential.id,
        name: result.name,
        description: result.description,
        information: result.information,
      );
      await _activityRepository.appendEvent(
        LocalActivityEvent.create(
          referentialId: widget.referential.id,
          campaignId: campaign.id,
          type: LocalActivityType.campaignCreated,
          title: campaignCreatedTitle,
          description: campaign.name,
        ),
      );
      final syncResult = await _syncAutomationService.pushLocalSnapshot(
        referential: widget.referential,
        activeUser: widget.activeUser,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${syncResult.title} — ${syncResult.message}'),
          ),
        );
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _deleteCampaign(LocalCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteCampaignDialog(campaign: campaign),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      await _campaignRepository.deleteCampaign(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );

      final syncResult = await _syncAutomationService.pushLocalSnapshot(
        referential: widget.referential,
        activeUser: widget.activeUser,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${syncResult.title} — ${syncResult.message}'),
          ),
        );
      }
      await _refresh();
    } on ServerCampaignStoreException catch (error) {
      if (mounted) {
        final message = switch (error.code) {
          ServerCampaignStoreErrorCode.revisionConflict => context.tr(
            'screen.campaign.manage.delete.revision_conflict',
            fallback:
                'La campagne a été modifiée sur un autre terminal. Recharge la liste avant de confirmer à nouveau sa suppression.',
          ),
          _ => context.tr(
            'screen.campaign.manage.delete.failed',
            fallback:
                'La suppression de la campagne a été refusée par le serveur.',
          ),
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Gérer les campagnes'),
      body: FutureBuilder<List<LocalCampaign>>(
        future: _campaignsFuture,
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

          final campaigns = snapshot.data ?? const <LocalCampaign>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeaderCard(
                    activeUser: widget.activeUser,
                    campaignCount: campaigns.length,
                    isWorking: _isWorking,
                    onCreate: _isWorking ? null : _createCampaign,
                  ),
                  const SizedBox(height: 12),
                  if (campaigns.isEmpty)
                    const _EmptyState()
                  else
                    for (final campaign in campaigns)
                      _ManagedCampaignCard(
                        campaign: campaign,
                        onDelete: _isWorking
                            ? null
                            : () => _deleteCampaign(campaign),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final AppUser activeUser;
  final int campaignCount;
  final bool isWorking;
  final VoidCallback? onCreate;

  const _HeaderCard({
    required this.activeUser,
    required this.campaignCount,
    required this.isWorking,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'screen.campaign.manage.header.title',
                          fallback: 'Administration des campagnes',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activeUser.displayName} · ${context.trText(activeUser.role.label)}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr(
                          'screen.campaign.manage.header.subtitle',
                          fallback:
                              'Créer une nouvelle campagne ou supprimer une campagne existante. La suppression efface aussi les réponses, les affectations et le journal de la campagne concernée.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.manage.chip.count',
                      fallback: '{count} campagne(s)',
                      values: {'count': campaignCount},
                    ),
                  ),
                ),
                if (isWorking)
                  Chip(
                    avatar: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: Text(
                      context.tr(
                        'sync.status.in_progress',
                        fallback: 'Synchronisation en cours',
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(
                    context.tr(
                      'screen.campaign.manage.create',
                      fallback: 'Créer une campagne',
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

class _ManagedCampaignCard extends StatelessWidget {
  final LocalCampaign campaign;
  final VoidCallback? onDelete;

  const _ManagedCampaignCard({required this.campaign, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.name, style: theme.textTheme.titleMedium),
                      if (campaign.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(campaign.description),
                      ],
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
                Chip(label: Text(_statusLabel(context, campaign.status))),
                Chip(
                  label: Text(
                    context.tr(
                      'common.updated_at_short',
                      fallback: 'Maj : {date}',
                      values: {'date': _formatDate(campaign.updatedAt)},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'common.created_at_short',
                      fallback: 'Créée : {date}',
                      values: {'date': _formatDate(campaign.createdAt)},
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('action.delete', fallback: 'Supprimer')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, LocalCampaignStatus status) {
    switch (status) {
      case LocalCampaignStatus.draft:
        return context.tr('campaign.status.draft', fallback: 'Brouillon');
      case LocalCampaignStatus.readyForReview:
        return context.tr(
          'campaign.status.ready_for_review',
          fallback: 'Prêt pour revue',
        );
      case LocalCampaignStatus.validated:
        return context.tr('campaign.status.validated', fallback: 'Validé');
      case LocalCampaignStatus.archived:
        return context.tr('campaign.status.archived', fallback: 'Archivé');
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _CreateCampaignDialog extends StatefulWidget {
  final IrnAssetInventory? inventory;

  const _CreateCampaignDialog({this.inventory});

  @override
  State<_CreateCampaignDialog> createState() => _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends State<_CreateCampaignDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedSystemId;

  IrnAssetInventory? get _inventory => widget.inventory;

  List<InformationSystemInfo> get _systems {
    final inventory = _inventory;
    if (inventory == null) {
      return const <InformationSystemInfo>[];
    }
    final systems = List<InformationSystemInfo>.from(
      inventory.informationSystems,
    )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return systems;
  }

  InformationSystemInfo? get _selectedSystem {
    final selected = _selectedSystemId;
    if (selected == null || selected.trim().isEmpty) {
      return null;
    }
    for (final system in _systems) {
      if (system.id == selected) {
        return system;
      }
    }
    return null;
  }

  CriticalFunctionInfo? _functionForSystem(InformationSystemInfo system) {
    final inventory = _inventory;
    if (inventory == null) {
      return null;
    }
    for (final function in inventory.criticalFunctions) {
      if (function.id == system.functionId) {
        return function;
      }
    }
    return null;
  }

  List<InformationAssetInfo> _assetsForSystem(InformationSystemInfo system) {
    final inventory = _inventory;
    if (inventory == null) {
      return const <InformationAssetInfo>[];
    }
    final assets = inventory.assetsForSystem(system.id)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return assets;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _selectSystem(String? systemId) {
    setState(() {
      _selectedSystemId = systemId;
      final system = _selectedSystem;
      if (system != null) {
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = context.tr(
            'screen.campaign.manage.default_name',
            fallback: 'IRN — {system}',
            values: {'system': system.name},
          );
        }
        if (_descriptionController.text.trim().isEmpty) {
          _descriptionController.text = context.tr(
            'screen.campaign.manage.default_description',
            fallback: 'Campagne de notation IRN des actifs du SI « {system} ».',
            values: {'system': system.name},
          );
        }
      }
    });
  }

  void _submit() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final system = _selectedSystem;
    CampaignInformation information = const CampaignInformation();
    if (system != null) {
      final function = _functionForSystem(system);
      final assets = _assetsForSystem(system);
      information = CampaignInformation(
        systemName: system.name,
        systemDescription: system.description,
        projectDirectorLastName: system.owner,
        criticalFunctionId: function?.id ?? '',
        criticalFunctionName: function?.name ?? '',
        informationSystemId: system.id,
        assets: assets
            .map(
              (asset) => CampaignInformationAsset(
                id: asset.id,
                name: asset.name,
                assetType: asset.assetType,
                criticality: asset.criticality,
                description: asset.description,
              ),
            )
            .toList(growable: false),
      );
    }

    Navigator.of(context).pop(
      _CampaignFormResult(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        information: information,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systems = _systems;
    final selectedSystem = _selectedSystem;
    final selectedAssets = selectedSystem == null
        ? const <InformationAssetInfo>[]
        : _assetsForSystem(selectedSystem);
    final selectedFunction = selectedSystem == null
        ? null
        : _functionForSystem(selectedSystem);

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'screen.campaign.manage.dialog.create.title',
          fallback: 'Créer une campagne',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 760,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (systems.isEmpty)
                const _InventoryUnavailableNotice()
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedSystemId,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'screen.campaign.manage.form.system',
                      fallback: 'Système d’information à évaluer',
                    ),
                    prefixIcon: const Icon(Icons.dns_outlined),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: '',
                      child: Text(
                        context.tr(
                          'screen.campaign.manage.form.free_campaign',
                          fallback: 'Campagne libre, sans SI rattaché',
                        ),
                      ),
                    ),
                    for (final system in systems)
                      DropdownMenuItem<String>(
                        value: system.id,
                        child: Text(system.name),
                      ),
                  ],
                  onChanged: (value) => _selectSystem(
                    value == null || value.trim().isEmpty ? null : value,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return null;
                    }
                    InformationSystemInfo? system;
                    for (final item in _systems) {
                      if (item.id == value) {
                        system = item;
                        break;
                      }
                    }
                    if (system == null) {
                      return context.tr(
                        'screen.campaign.manage.validation.unknown_system',
                        fallback: 'SI inconnu.',
                      );
                    }
                    if (_assetsForSystem(system).isEmpty) {
                      return context.tr(
                        'screen.campaign.manage.validation.no_assets',
                        fallback: 'Le SI sélectionné ne contient aucun actif.',
                      );
                    }
                    return null;
                  },
                ),
                if (selectedSystem != null) ...[
                  const SizedBox(height: 10),
                  _SelectedSystemPreview(
                    system: selectedSystem,
                    function: selectedFunction,
                    assetCount: selectedAssets.length,
                  ),
                ],
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: InputDecoration(
                  labelText: context.tr(
                    'screen.campaign.manage.form.name',
                    fallback: 'Nom de la campagne',
                  ),
                  prefixIcon: const Icon(Icons.drive_file_rename_outline),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return context.tr(
                      'screen.campaign.manage.validation.name_required',
                      fallback: 'Le nom de la campagne est obligatoire.',
                    );
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: context.tr(
                    'common.description',
                    fallback: 'Description',
                  ),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('action.cancel', fallback: 'Annuler')),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add),
          label: Text(context.tr('action.create', fallback: 'Créer')),
        ),
      ],
    );
  }
}

class _InventoryUnavailableNotice extends StatelessWidget {
  const _InventoryUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr(
                  'screen.campaign.manage.inventory_unavailable',
                  fallback:
                      'Aucun inventaire SI disponible sur ce terminal. Vous pouvez créer une campagne libre, ou renseigner d’abord les fonctions critiques, SI et actifs.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedSystemPreview extends StatelessWidget {
  final InformationSystemInfo system;
  final CriticalFunctionInfo? function;
  final int assetCount;

  const _SelectedSystemPreview({
    required this.system,
    required this.function,
    required this.assetCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'screen.campaign.manage.scope.title',
                fallback: 'Périmètre de notation',
              ),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'screen.campaign.manage.scope.function',
                fallback: 'Fonction critique : {function}',
                values: {
                  'function':
                      function?.name ??
                      context.tr(
                        'common.not_provided',
                        fallback: 'non renseignée',
                      ),
                },
              ),
            ),
            Text(
              context.tr(
                'screen.campaign.manage.scope.system',
                fallback: 'SI : {system}',
                values: {'system': system.name},
              ),
            ),
            if (system.owner.trim().isNotEmpty)
              Text(
                context.tr(
                  'screen.campaign.manage.scope.owner',
                  fallback: 'Porteur SI : {owner}',
                  values: {'owner': system.owner},
                ),
              ),
            Text(
              context.tr(
                'screen.campaign.manage.scope.assets',
                fallback: 'Actifs à noter : {count}',
                values: {'count': assetCount},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteCampaignDialog extends StatelessWidget {
  final LocalCampaign campaign;

  const _DeleteCampaignDialog({required this.campaign});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'screen.campaign.manage.delete.title',
          fallback: 'Supprimer la campagne ?',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(campaign.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(
              context.tr(
                'screen.campaign.manage.delete.body',
                fallback:
                    'Cette action supprime la campagne de ce terminal, ses réponses, ses affectations et son journal. La suppression sera ensuite publiée au serveur pour synchroniser les autres terminaux.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('action.cancel', fallback: 'Annuler')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete_outline),
          label: Text(context.tr('action.delete', fallback: 'Supprimer')),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
        ),
      ],
    );
  }
}

class _CampaignFormResult {
  final String name;
  final String description;
  final CampaignInformation information;

  const _CampaignFormResult({
    required this.name,
    required this.description,
    this.information = const CampaignInformation(),
  });
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.folder_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'screen.campaign.manage.empty.title',
                fallback: 'Aucune campagne.',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'screen.campaign.manage.empty.subtitle',
                fallback:
                    'Créez une première campagne depuis le bouton ci-dessus.',
              ),
            ),
          ],
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
            Text(
              context.tr(
                'screen.campaign.manage.error.load',
                fallback:
                    'Impossible de charger la gestion des campagnes : {error}',
                values: {'error': error},
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('action.retry', fallback: 'Réessayer')),
            ),
          ],
        ),
      ),
    );
  }
}
