import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_asset_inventory.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/utils/openirn_uuid.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class AssetInventoryManagementScreen extends StatefulWidget {
  final AppUser activeUser;

  const AssetInventoryManagementScreen({required this.activeUser, super.key});

  @override
  State<AssetInventoryManagementScreen> createState() =>
      _AssetInventoryManagementScreenState();
}

class _AssetInventoryManagementScreenState
    extends State<AssetInventoryManagementScreen> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _accessPolicy = const AccessPolicyService();

  late Future<_InventoryStateData> _future;
  bool _working = false;
  bool _assetsSectionExpanded = false;
  bool _systemsSectionExpanded = false;
  bool _functionsSectionExpanded = false;

  @override
  void initState() {
    super.initState();
    _future = _loadInventory();
  }

  Future<_InventoryStateData> _loadInventory() async {
    if (!_accessPolicy.canManageInformationAssets(widget.activeUser)) {
      return _InventoryStateData(
        configuration: SyncConfiguration.empty(),
        inventory: IrnAssetInventory.empty(),
        available: false,
        title: 'Accès refusé',
        message:
            'La gestion des fonctions critiques, systèmes d’information et actifs est réservée aux administrateurs et pilotes IRN.',
      );
    }
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _InventoryStateData(
        configuration: configuration,
        inventory: IrnAssetInventory.empty(tenantId: configuration.tenantId),
        available: false,
        title: 'Serveur non configuré',
        message:
            'La synchronisation serveur n’est pas configurée sur ce terminal. Impossible de gérer l’inventaire SI.',
      );
    }
    final result = await _apiClient.loadAssetInventory(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
    return _InventoryStateData(
      configuration: configuration,
      inventory: result.inventory,
      available: result.isAvailable,
      title: result.title,
      message: result.message,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadInventory();
    });
    await _future;
  }

  Future<void> _applyResult(Future<OpenIrnApiInventoryResult> future) async {
    setState(() {
      _working = true;
    });
    try {
      final result = await future;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.trText(result.title)} — ${context.trText(result.message)}',
          ),
        ),
      );
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _createFunction(_InventoryStateData state) async {
    final form = await showDialog<_FunctionFormResult>(
      context: context,
      builder: (context) =>
          _FunctionDialog(systems: state.inventory.informationSystems),
    );
    if (form == null) {
      return;
    }
    setState(() {
      _functionsSectionExpanded = true;
    });
    final functionId = newOpenIrnUuid();
    await _applyResult(
      _createFunctionAndUpdateSystems(
        state: state,
        functionId: functionId,
        form: form,
      ),
    );
  }

  Future<OpenIrnApiInventoryResult> _createFunctionAndUpdateSystems({
    required _InventoryStateData state,
    required String functionId,
    required _FunctionFormResult form,
  }) async {
    final createResult = await _apiClient.createCriticalFunction(
      baseUrl: state.configuration.apiBaseUrl,
      tenantId: state.configuration.tenantId,
      apiToken: state.configuration.apiToken,
      functionId: functionId,
      name: form.name,
      description: form.description,
    );
    if (!createResult.isAvailable) {
      return createResult;
    }
    return _replaceFunctionSystems(
      state: state,
      result: createResult,
      functionId: functionId,
      selectedSystemIds: form.systemIds,
    );
  }

  Future<void> _editFunction(
    _InventoryStateData state,
    CriticalFunctionInfo function,
  ) async {
    final form = await showDialog<_FunctionFormResult>(
      context: context,
      builder: (context) => _FunctionDialog(
        function: function,
        systems: state.inventory.informationSystems,
        selectedSystemIds: state.inventory
            .systemsForFunction(function.id)
            .map((system) => system.id)
            .toSet(),
      ),
    );
    if (form == null) {
      return;
    }
    setState(() {
      _functionsSectionExpanded = true;
    });
    await _applyResult(
      _updateFunctionAndSystems(state: state, function: function, form: form),
    );
  }

  Future<OpenIrnApiInventoryResult> _updateFunctionAndSystems({
    required _InventoryStateData state,
    required CriticalFunctionInfo function,
    required _FunctionFormResult form,
  }) async {
    final updateResult = await _apiClient.updateCriticalFunction(
      baseUrl: state.configuration.apiBaseUrl,
      tenantId: state.configuration.tenantId,
      apiToken: state.configuration.apiToken,
      functionId: function.id,
      name: form.name,
      description: form.description,
    );
    if (!updateResult.isAvailable) {
      return updateResult;
    }
    return _replaceFunctionSystems(
      state: state,
      result: updateResult,
      functionId: function.id,
      selectedSystemIds: form.systemIds,
    );
  }

  Future<OpenIrnApiInventoryResult> _replaceFunctionSystems({
    required _InventoryStateData state,
    required OpenIrnApiInventoryResult result,
    required String functionId,
    required List<String> selectedSystemIds,
  }) async {
    final selectedIds = selectedSystemIds.toSet();
    final systems = List<InformationSystemInfo>.from(
      result.inventory.informationSystems,
    );
    var currentResult = result;
    for (final system in systems) {
      final functionIds = system.functionIds.toSet();
      final wasLinked = functionIds.contains(functionId);
      final shouldBeLinked = selectedIds.contains(system.id);
      if (wasLinked == shouldBeLinked) {
        continue;
      }
      if (shouldBeLinked) {
        functionIds.add(functionId);
      } else {
        functionIds.remove(functionId);
      }
      currentResult = await _apiClient.updateInformationSystem(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemId: system.id,
        functionIds: functionIds.toList(growable: false),
        name: system.name,
        description: system.description,
        owner: system.owner,
      );
      if (!currentResult.isAvailable) {
        return currentResult;
      }
    }
    if (identical(currentResult, result)) {
      return result;
    }
    return OpenIrnApiInventoryResult(
      status: currentResult.status,
      url: result.url,
      statusCode: result.statusCode,
      title: result.title,
      message: result.message,
      tenantId: currentResult.tenantId,
      inventory: currentResult.inventory,
      responseBody: currentResult.responseBody,
    );
  }

  Future<void> _deleteFunction(
    _InventoryStateData state,
    CriticalFunctionInfo function,
  ) async {
    final confirmed = await _confirmDelete(
      title: context.tr('inventory.confirm.delete_function.title'),
      message: context.tr(
        'inventory.confirm.delete_function.message',
        values: {'name': function.name},
      ),
    );
    if (!confirmed) {
      return;
    }
    await _applyResult(
      _apiClient.deleteCriticalFunction(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        functionId: function.id,
      ),
    );
  }

  Future<void> _createSystem(_InventoryStateData state) async {
    final form = await showDialog<_SystemFormResult>(
      context: context,
      builder: (context) => const _SystemDialog(),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.createInformationSystem(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        functionIds: const <String>[],
        name: form.name,
        description: form.description,
        owner: form.owner,
      ),
    );
  }

  Future<void> _editSystem(
    _InventoryStateData state,
    InformationSystemInfo system,
  ) async {
    final form = await showDialog<_SystemFormResult>(
      context: context,
      builder: (context) => _SystemDialog(
        system: system,
        assets: state.inventory.assets,
        selectedAssetIds: state.inventory
            .assetsForSystem(system.id)
            .map((asset) => asset.id)
            .toSet(),
      ),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _updateSystemAndAssets(state: state, system: system, form: form),
    );
  }

  Future<OpenIrnApiInventoryResult> _updateSystemAndAssets({
    required _InventoryStateData state,
    required InformationSystemInfo system,
    required _SystemFormResult form,
  }) async {
    final updateResult = await _apiClient.updateInformationSystem(
      baseUrl: state.configuration.apiBaseUrl,
      tenantId: state.configuration.tenantId,
      apiToken: state.configuration.apiToken,
      systemId: system.id,
      functionIds: system.functionIds,
      name: form.name,
      description: form.description,
      owner: form.owner,
    );
    if (!updateResult.isAvailable) {
      return updateResult;
    }
    return _apiClient.replaceInformationSystemAssets(
      baseUrl: state.configuration.apiBaseUrl,
      tenantId: state.configuration.tenantId,
      apiToken: state.configuration.apiToken,
      systemId: system.id,
      assetIds: form.assetIds,
    );
  }

  Future<void> _deleteSystem(
    _InventoryStateData state,
    InformationSystemInfo system,
  ) async {
    final confirmed = await _confirmDelete(
      title: context.tr('inventory.confirm.delete_system.title'),
      message: context.tr(
        'inventory.confirm.delete_system.message',
        values: {'name': system.name},
      ),
    );
    if (!confirmed) {
      return;
    }
    await _applyResult(
      _apiClient.deleteInformationSystem(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemId: system.id,
      ),
    );
  }

  Future<void> _createAsset(_InventoryStateData state) async {
    final form = await showDialog<_AssetFormResult>(
      context: context,
      builder: (context) => const _AssetDialog(),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.createInformationAsset(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemIds: form.systemIds,
        name: form.name,
        assetType: form.assetType,
        criticality: form.criticality,
        description: form.description,
      ),
    );
  }

  Future<void> _editAsset(
    _InventoryStateData state,
    InformationAssetInfo asset,
  ) async {
    final form = await showDialog<_AssetFormResult>(
      context: context,
      builder: (context) => _AssetDialog(asset: asset),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.updateInformationAsset(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        assetId: asset.id,
        systemIds: form.systemIds,
        name: form.name,
        assetType: form.assetType,
        criticality: form.criticality,
        description: form.description,
      ),
    );
  }

  Future<void> _deleteAsset(
    _InventoryStateData state,
    InformationAssetInfo asset,
  ) async {
    final confirmed = await _confirmDelete(
      title: context.tr('inventory.confirm.delete_asset.title'),
      message: context.tr(
        'inventory.confirm.delete_asset.message',
        values: {'name': asset.name},
      ),
    );
    if (!confirmed) {
      return;
    }
    await _applyResult(
      _apiClient.deleteInformationAsset(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        assetId: asset.id,
      ),
    );
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('action.cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: Text(context.tr('action.delete')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: context.tr('inventory.title'),
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh_inventory',
            label: context.tr('action.refresh'),
            icon: Icons.refresh,
            onPressed: _working ? null : _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_InventoryStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = snapshot.data;
          if (state == null) {
            return _InventoryErrorCard(
              title: context.tr('inventory.error.missing_state.title'),
              message: context.tr('inventory.error.missing_state.message'),
            );
          }
          if (!state.available) {
            return _InventoryErrorCard(
              title: context.trText(state.title),
              message: context.trText(state.message),
            );
          }
          return _InventoryContent(
            state: state,
            working: _working,
            assetsSectionExpanded: _assetsSectionExpanded,
            onAssetsSectionExpansionChanged: (expanded) {
              if (_assetsSectionExpanded == expanded) {
                return;
              }
              setState(() {
                _assetsSectionExpanded = expanded;
              });
            },
            onCreateFunction: () => _createFunction(state),
            onEditFunction: (function) => _editFunction(state, function),
            onDeleteFunction: (function) => _deleteFunction(state, function),
            functionsSectionExpanded: _functionsSectionExpanded,
            onFunctionsSectionExpansionChanged: (expanded) {
              if (_functionsSectionExpanded == expanded) {
                return;
              }
              setState(() {
                _functionsSectionExpanded = expanded;
              });
            },
            onCreateSystem: () => _createSystem(state),
            onEditSystem: (system) => _editSystem(state, system),
            onDeleteSystem: (system) => _deleteSystem(state, system),
            systemsSectionExpanded: _systemsSectionExpanded,
            onSystemsSectionExpansionChanged: (expanded) {
              if (_systemsSectionExpanded == expanded) {
                return;
              }
              setState(() {
                _systemsSectionExpanded = expanded;
              });
            },
            onCreateAsset: () => _createAsset(state),
            onEditAsset: (asset) => _editAsset(state, asset),
            onDeleteAsset: (asset) => _deleteAsset(state, asset),
          );
        },
      ),
    );
  }
}

class _InventoryStateData {
  final SyncConfiguration configuration;
  final IrnAssetInventory inventory;
  final bool available;
  final String title;
  final String message;

  const _InventoryStateData({
    required this.configuration,
    required this.inventory,
    required this.available,
    required this.title,
    required this.message,
  });
}

class _InventoryContent extends StatelessWidget {
  final _InventoryStateData state;
  final bool working;
  final bool assetsSectionExpanded;
  final ValueChanged<bool> onAssetsSectionExpansionChanged;
  final VoidCallback onCreateFunction;
  final ValueChanged<CriticalFunctionInfo> onEditFunction;
  final ValueChanged<CriticalFunctionInfo> onDeleteFunction;
  final bool functionsSectionExpanded;
  final ValueChanged<bool> onFunctionsSectionExpansionChanged;
  final VoidCallback onCreateSystem;
  final ValueChanged<InformationSystemInfo> onEditSystem;
  final ValueChanged<InformationSystemInfo> onDeleteSystem;
  final bool systemsSectionExpanded;
  final ValueChanged<bool> onSystemsSectionExpansionChanged;
  final VoidCallback onCreateAsset;
  final ValueChanged<InformationAssetInfo> onEditAsset;
  final ValueChanged<InformationAssetInfo> onDeleteAsset;

  const _InventoryContent({
    required this.state,
    required this.working,
    required this.assetsSectionExpanded,
    required this.onAssetsSectionExpansionChanged,
    required this.onCreateFunction,
    required this.onEditFunction,
    required this.onDeleteFunction,
    required this.functionsSectionExpanded,
    required this.onFunctionsSectionExpansionChanged,
    required this.onCreateSystem,
    required this.onEditSystem,
    required this.onDeleteSystem,
    required this.systemsSectionExpanded,
    required this.onSystemsSectionExpansionChanged,
    required this.onCreateAsset,
    required this.onEditAsset,
    required this.onDeleteAsset,
  });

  @override
  Widget build(BuildContext context) {
    final inventory = state.inventory;
    final overviewDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('inventory.overview.title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'inventory.overview.workspace',
            values: {
              'workspace': inventory.tenantDisplayName.isEmpty
                  ? state.configuration.tenantId
                  : inventory.tenantDisplayName,
            },
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(
                context.tr(
                  'inventory.count.critical_functions',
                  values: {'count': inventory.criticalFunctions.length},
                ),
              ),
            ),
            Chip(
              label: Text(
                context.tr(
                  'inventory.count.information_systems',
                  values: {'count': inventory.informationSystems.length},
                ),
              ),
            ),
            Chip(
              label: Text(
                context.tr(
                  'inventory.count.assets',
                  values: {'count': inventory.assets.length},
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(context.tr('inventory.overview.shared_asset_model')),
      ],
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone = constraints.maxWidth < 600;
                    final isTablet = constraints.maxWidth < 900;
                    final maxIllustrationWidth = isPhone
                        ? 357.0
                        : isTablet
                        ? 612.0
                        : 408.0;
                    final illustrationWidth = math.min(
                      constraints.maxWidth,
                      maxIllustrationWidth,
                    );
                    final cacheWidth = math.min(
                      1200,
                      math.max(
                        1,
                        (illustrationWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                      ),
                    );
                    final illustration = Image.asset(
                      'assets/images/openirn_graph.webp',
                      width: illustrationWidth,
                      cacheWidth: cacheWidth,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      semanticLabel: context.tr(
                        'inventory.overview.graph_semantics',
                      ),
                    );
                    if (isTablet) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          overviewDetails,
                          const SizedBox(height: 18),
                          Center(child: illustration),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: overviewDetails),
                        const SizedBox(width: 28),
                        illustration,
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _InventorySection(
              storageKey: const PageStorageKey<String>(
                'inventory-assets-section',
              ),
              icon: Icons.inventory_2_outlined,
              title: context.tr('inventory.section.assets.title'),
              description: context.tr('inventory.section.assets.description'),
              initiallyExpanded: assetsSectionExpanded,
              onExpansionChanged: onAssetsSectionExpansionChanged,
              actionLabel: context.tr('inventory.action.add_asset'),
              onAction: working ? null : onCreateAsset,
              emptyLabel: context.tr('inventory.empty.asset_catalog'),
              children: [
                for (final asset in inventory.assets)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(asset.name),
                    subtitle: Text(
                      [
                        if (asset.assetType.isNotEmpty) asset.assetType,
                        _assetCriticalityLabel(context, asset.criticality),
                        context.tr(
                          'inventory.count.linked_systems',
                          values: {'count': asset.systemIds.length},
                        ),
                        context.tr(
                          asset.isAssessed
                              ? 'inventory.asset.assessment.assessed'
                              : 'inventory.asset.assessment.not_assessed',
                        ),
                        if (asset.description.isNotEmpty) asset.description,
                      ].join(' — '),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: working ? null : () => onEditAsset(asset),
                          tooltip: context.tr('inventory.tooltip.edit_asset'),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: working || asset.systemIds.isNotEmpty
                              ? null
                              : () => onDeleteAsset(asset),
                          tooltip: context.tr('inventory.tooltip.delete_asset'),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _InventorySection(
              storageKey: const PageStorageKey<String>(
                'inventory-systems-section',
              ),
              icon: Icons.dns_outlined,
              title: context.tr('inventory.section.systems.title'),
              description: context.tr('inventory.section.systems.description'),
              initiallyExpanded: systemsSectionExpanded,
              onExpansionChanged: onSystemsSectionExpansionChanged,
              actionLabel: context.tr('inventory.action.add_system'),
              onAction: working ? null : onCreateSystem,
              emptyLabel: context.tr('inventory.empty.system_catalog'),
              children: [
                for (final system in inventory.informationSystems)
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(system.name),
                    subtitle: Text(
                      [
                        if (system.owner.isNotEmpty)
                          context.tr(
                            'inventory.system.owner',
                            values: {'owner': system.owner},
                          ),
                        context.tr(
                          'inventory.count.linked_functions',
                          values: {'count': system.functionIds.length},
                        ),
                        context.tr(
                          'inventory.count.assets',
                          values: {
                            'count': inventory
                                .assetsForSystem(system.id)
                                .length,
                          },
                        ),
                        if (system.description.isNotEmpty) system.description,
                      ].join(' — '),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: working
                              ? null
                              : () => onEditSystem(system),
                          tooltip: context.tr('action.edit'),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: working || system.functionIds.isNotEmpty
                              ? null
                              : () => onDeleteSystem(system),
                          tooltip: context.tr('action.delete'),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _InventorySection(
              storageKey: const PageStorageKey<String>(
                'inventory-functions-section',
              ),
              icon: Icons.account_tree_outlined,
              title: context.tr('inventory.section.functions.title'),
              description: context.tr(
                'inventory.section.functions.description',
              ),
              initiallyExpanded: functionsSectionExpanded,
              onExpansionChanged: onFunctionsSectionExpansionChanged,
              actionLabel: context.tr('inventory.action.add_function'),
              onAction: working ? null : onCreateFunction,
              emptyLabel: context.tr('inventory.empty.functions'),
              children: [
                for (final function in inventory.criticalFunctions)
                  ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(function.name),
                    subtitle: Text(
                      [
                        context.tr(
                          'inventory.count.systems_short',
                          values: {
                            'count': inventory
                                .systemsForFunction(function.id)
                                .length,
                          },
                        ),
                        if (function.description.isNotEmpty)
                          function.description,
                      ].join(' — '),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: working
                              ? null
                              : () => onEditFunction(function),
                          tooltip: context.tr('action.edit'),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: working
                              ? null
                              : () => onDeleteFunction(function),
                          tooltip: context.tr('action.delete'),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
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

String _assetCriticalityLabel(BuildContext context, String value) {
  switch (value.trim()) {
    case '1':
      return context.tr('inventory.asset.criticality.n1');
    case '2':
      return context.tr('inventory.asset.criticality.n2');
    case '3':
      return context.tr('inventory.asset.criticality.n3');
    case '4':
      return context.tr('inventory.asset.criticality.n4');
  }
  return context.tr('inventory.asset.criticality.missing');
}

class _InventorySection extends StatelessWidget {
  final PageStorageKey<String> storageKey;
  final IconData icon;
  final String title;
  final String description;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final String actionLabel;
  final VoidCallback? onAction;
  final String emptyLabel;
  final List<Widget> children;

  const _InventorySection({
    required this.storageKey,
    required this.icon,
    required this.title,
    required this.description,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    required this.actionLabel,
    required this.onAction,
    required this.emptyLabel,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: storageKey,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        controlAffinity: ListTileControlAffinity.trailing,
        leading: Icon(icon),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(description),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ),
          const Divider(height: 24),
          if (children.isEmpty) Text(emptyLabel) else ...children,
        ],
      ),
    );
  }
}

class _InventoryErrorCard extends StatelessWidget {
  final String title;
  final String message;

  const _InventoryErrorCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FunctionFormResult {
  final List<String> systemIds;
  final String name;
  final String description;

  const _FunctionFormResult({
    required this.systemIds,
    required this.name,
    required this.description,
  });
}

class _FunctionDialog extends StatefulWidget {
  final CriticalFunctionInfo? function;
  final List<InformationSystemInfo> systems;
  final Set<String> selectedSystemIds;

  const _FunctionDialog({
    this.function,
    required this.systems,
    this.selectedSystemIds = const <String>{},
  });

  @override
  State<_FunctionDialog> createState() => _FunctionDialogState();
}

class _FunctionDialogState extends State<_FunctionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Set<String> _selectedSystemIds;

  @override
  void initState() {
    super.initState();
    _selectedSystemIds = Set<String>.from(widget.selectedSystemIds);
    _nameController = TextEditingController(text: widget.function?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.function?.description ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _FunctionFormResult(
        systemIds: _selectedSystemIds.toList(growable: false),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.function != null;
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        editing
            ? context.tr('inventory.dialog.function.edit_title')
            : context.tr('inventory.dialog.function.create_title'),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: InputDecoration(
                  labelText: context.tr('inventory.field.function_name'),
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? context.tr('validation.name_required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.tr('field.description'),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              FormField<Set<String>>(
                initialValue: Set<String>.from(_selectedSystemIds),
                validator: (systemIds) =>
                    (systemIds ?? const <String>{}).isEmpty
                    ? context.tr('inventory.validation.system_required')
                    : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 32),
                    Text(
                      context.tr('inventory.field.linked_systems'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (widget.systems.isEmpty)
                      Text(context.tr('inventory.empty.system_catalog'))
                    else
                      for (final system in widget.systems)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selectedSystemIds.contains(system.id),
                          title: Text(system.name),
                          subtitle: system.owner.isEmpty
                              ? null
                              : Text(
                                  context.tr(
                                    'inventory.system.owner',
                                    values: {'owner': system.owner},
                                  ),
                                ),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedSystemIds.add(system.id);
                              } else {
                                _selectedSystemIds.remove(system.id);
                              }
                            });
                            field.didChange(
                              Set<String>.from(_selectedSystemIds),
                            );
                          },
                        ),
                    if (field.hasError) ...[
                      const SizedBox(height: 4),
                      Text(
                        field.errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('action.cancel')),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: Text(context.tr('action.save')),
        ),
      ],
    );
  }
}

class _SystemFormResult {
  final List<String> assetIds;
  final String name;
  final String description;
  final String owner;

  const _SystemFormResult({
    required this.assetIds,
    required this.name,
    required this.description,
    required this.owner,
  });
}

class _SystemDialog extends StatefulWidget {
  final InformationSystemInfo? system;
  final List<InformationAssetInfo> assets;
  final Set<String> selectedAssetIds;

  const _SystemDialog({
    this.system,
    this.assets = const <InformationAssetInfo>[],
    this.selectedAssetIds = const <String>{},
  });

  @override
  State<_SystemDialog> createState() => _SystemDialogState();
}

class _SystemDialogState extends State<_SystemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ownerController;
  late Set<String> _selectedAssetIds;

  @override
  void initState() {
    super.initState();
    _selectedAssetIds = Set<String>.from(widget.selectedAssetIds);
    _nameController = TextEditingController(text: widget.system?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.system?.description ?? '',
    );
    _ownerController = TextEditingController(text: widget.system?.owner ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _ownerController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _SystemFormResult(
        assetIds: _selectedAssetIds.toList(growable: false),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        owner: _ownerController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.system != null;
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        editing
            ? context.tr('inventory.dialog.system.edit_title')
            : context.tr('inventory.dialog.system.create_title'),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: InputDecoration(
                  labelText: context.tr('inventory.field.system_name'),
                  prefixIcon: const Icon(Icons.dns_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? context.tr('validation.name_required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerController,
                decoration: InputDecoration(
                  labelText: context.tr('inventory.field.system_owner'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.tr('field.description'),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              if (editing) ...[
                const Divider(height: 32),
                Text(
                  context.tr('inventory.action.manage_assets'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(context.tr('inventory.dialog.system_assets.help')),
                const SizedBox(height: 8),
                if (widget.assets.isEmpty)
                  Text(context.tr('inventory.empty.asset_catalog'))
                else
                  for (final asset in widget.assets)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selectedAssetIds.contains(asset.id),
                      title: Text(asset.name),
                      subtitle: Text(
                        [
                          if (asset.assetType.isNotEmpty) asset.assetType,
                          _assetCriticalityLabel(context, asset.criticality),
                        ].join(' — '),
                      ),
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedAssetIds.add(asset.id);
                          } else {
                            _selectedAssetIds.remove(asset.id);
                          }
                        });
                      },
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('action.cancel')),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: Text(context.tr('action.save')),
        ),
      ],
    );
  }
}

class _AssetFormResult {
  final List<String> systemIds;
  final String name;
  final String assetType;
  final String criticality;
  final String description;

  const _AssetFormResult({
    required this.systemIds,
    required this.name,
    required this.assetType,
    required this.criticality,
    required this.description,
  });
}

class _AssetDialog extends StatefulWidget {
  final InformationAssetInfo? asset;

  const _AssetDialog({this.asset});

  @override
  State<_AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<_AssetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _descriptionController;
  late String _criticality;

  @override
  void initState() {
    super.initState();
    final existingCriticality = widget.asset?.criticality.trim() ?? '';
    _criticality = <String>{'1', '2', '3', '4'}.contains(existingCriticality)
        ? existingCriticality
        : '1';
    _nameController = TextEditingController(text: widget.asset?.name ?? '');
    _typeController = TextEditingController(
      text: widget.asset?.assetType ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.asset?.description ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _AssetFormResult(
        systemIds: widget.asset?.systemIds ?? const <String>[],
        name: _nameController.text.trim(),
        assetType: _typeController.text.trim(),
        criticality: _criticality,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.asset != null;
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        editing
            ? context.tr('inventory.dialog.asset.edit_title')
            : context.tr('inventory.dialog.asset.create_title'),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 620,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: InputDecoration(
                  labelText: context.tr('inventory.field.asset_name'),
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? context.tr('validation.name_required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _typeController,
                decoration: InputDecoration(
                  labelText: context.tr('inventory.field.asset_type'),
                  hintText: context.tr('inventory.field.asset_type_hint'),
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _criticality,
                items: [
                  DropdownMenuItem(
                    value: '1',
                    child: Text(context.tr('inventory.asset.criticality.1')),
                  ),
                  DropdownMenuItem(
                    value: '2',
                    child: Text(context.tr('inventory.asset.criticality.2')),
                  ),
                  DropdownMenuItem(
                    value: '3',
                    child: Text(context.tr('inventory.asset.criticality.3')),
                  ),
                  DropdownMenuItem(
                    value: '4',
                    child: Text(context.tr('inventory.asset.criticality.4')),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: context.tr('inventory.field.asset_criticality'),
                  prefixIcon: const Icon(Icons.flag_outlined),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? context.tr('inventory.validation.criticality_required')
                    : null,
                onChanged: (value) =>
                    setState(() => _criticality = value ?? '1'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.tr('field.description'),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('action.cancel')),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: Text(context.tr('action.save')),
        ),
      ],
    );
  }
}
