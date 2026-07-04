import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/files/local_excel_file_service.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_asset_inventory.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
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
  final _excelFileService = const LocalExcelFileService();
  final _accessPolicy = const AccessPolicyService();

  late Future<_InventoryStateData> _future;
  bool _working = false;

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
        SnackBar(content: Text('${result.title} — ${result.message}')),
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
      builder: (context) => const _FunctionDialog(),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.createCriticalFunction(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        name: form.name,
        description: form.description,
      ),
    );
  }

  Future<void> _editFunction(
    _InventoryStateData state,
    CriticalFunctionInfo function,
  ) async {
    final form = await showDialog<_FunctionFormResult>(
      context: context,
      builder: (context) => _FunctionDialog(function: function),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.updateCriticalFunction(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        functionId: function.id,
        name: form.name,
        description: form.description,
      ),
    );
  }

  Future<void> _deleteFunction(
    _InventoryStateData state,
    CriticalFunctionInfo function,
  ) async {
    final confirmed = await _confirmDelete(
      title: 'Supprimer la fonction critique ?',
      message:
          'La fonction « ${function.name} » sera supprimée avec ses systèmes d’information et actifs associés.',
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

  Future<void> _createSystem(
    _InventoryStateData state,
    CriticalFunctionInfo function,
  ) async {
    final form = await showDialog<_SystemFormResult>(
      context: context,
      builder: (context) => _SystemDialog(
        functions: state.inventory.criticalFunctions,
        initialFunctionId: function.id,
      ),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.createInformationSystem(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        functionId: form.functionId,
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
        functions: state.inventory.criticalFunctions,
        system: system,
      ),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.updateInformationSystem(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemId: system.id,
        functionId: form.functionId,
        name: form.name,
        description: form.description,
        owner: form.owner,
      ),
    );
  }

  Future<void> _deleteSystem(
    _InventoryStateData state,
    InformationSystemInfo system,
  ) async {
    final confirmed = await _confirmDelete(
      title: 'Supprimer le système d’information ?',
      message:
          'Le SI « ${system.name} » sera supprimé avec les actifs associés.',
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

  Future<void> _createAsset(
    _InventoryStateData state,
    InformationSystemInfo system,
  ) async {
    final form = await showDialog<_AssetFormResult>(
      context: context,
      builder: (context) => _AssetDialog(
        systems: state.inventory.informationSystems,
        initialSystemId: system.id,
      ),
    );
    if (form == null) {
      return;
    }
    await _applyResult(
      _apiClient.createInformationAsset(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemId: form.systemId,
        name: form.name,
        assetType: form.assetType,
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
      builder: (context) => _AssetDialog(
        systems: state.inventory.informationSystems,
        asset: asset,
      ),
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
        systemId: form.systemId,
        name: form.name,
        assetType: form.assetType,
        description: form.description,
      ),
    );
  }

  Future<void> _deleteAsset(
    _InventoryStateData state,
    InformationAssetInfo asset,
  ) async {
    final confirmed = await _confirmDelete(
      title: 'Supprimer l’actif ?',
      message: 'L’actif « ${asset.name} » sera supprimé de l’inventaire SI.',
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

  Future<void> _exportSystemInventory(
    _InventoryStateData state,
    InformationSystemInfo system,
  ) async {
    setState(() {
      _working = true;
    });
    try {
      final result = await _apiClient.exportAssetInventoryExcel(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemId: system.id,
      );
      if (!mounted) {
        return;
      }
      if (!result.isAvailable || result.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.title} — ${result.message}')),
        );
        return;
      }
      final savedPath = await _excelFileService.saveExcel(
        bytes: result.bytes!,
        suggestedName: result.suggestedFileName,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'Export Excel annulé.'
                : 'Actifs du SI « ${system.name} » exportés : $savedPath',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _importSystemInventory(
    _InventoryStateData state,
    InformationSystemInfo system,
  ) async {
    final file = await _excelFileService.pickExcel();
    if (file == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer les actifs du SI ?'),
        content: Text(
          'Le fichier « ${file.name} » remplacera uniquement la liste des actifs du SI « ${system.name} ». La colonne ID actif permet de mettre à jour les actifs existants ; les lignes sans ID créent de nouveaux actifs. La fonction critique, le SI, les campagnes et notes IRN ne seront pas modifiés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Importer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _working = true;
    });
    try {
      final result = await _apiClient.importAssetInventoryExcel(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        systemId: system.id,
        bytes: file.bytes,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.title} — ${result.message}')),
      );
      if (result.isAvailable) {
        await _refresh();
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
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
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
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
        title: 'Fonctions critiques & actifs',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh_inventory',
            label: 'Actualiser',
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
            return const _InventoryErrorCard(
              title: 'État absent',
              message: 'Impossible de charger l’inventaire SI.',
            );
          }
          if (!state.available) {
            return _InventoryErrorCard(
              title: state.title,
              message: state.message,
            );
          }
          return _InventoryContent(
            state: state,
            working: _working,
            onCreateFunction: () => _createFunction(state),
            onEditFunction: (function) => _editFunction(state, function),
            onDeleteFunction: (function) => _deleteFunction(state, function),
            onCreateSystem: (function) => _createSystem(state, function),
            onEditSystem: (system) => _editSystem(state, system),
            onDeleteSystem: (system) => _deleteSystem(state, system),
            onImportSystemInventory: (system) =>
                _importSystemInventory(state, system),
            onExportSystemInventory: (system) =>
                _exportSystemInventory(state, system),
            onCreateAsset: (system) => _createAsset(state, system),
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
  final VoidCallback onCreateFunction;
  final ValueChanged<CriticalFunctionInfo> onEditFunction;
  final ValueChanged<CriticalFunctionInfo> onDeleteFunction;
  final ValueChanged<CriticalFunctionInfo> onCreateSystem;
  final ValueChanged<InformationSystemInfo> onEditSystem;
  final ValueChanged<InformationSystemInfo> onDeleteSystem;
  final ValueChanged<InformationSystemInfo> onImportSystemInventory;
  final ValueChanged<InformationSystemInfo> onExportSystemInventory;
  final ValueChanged<InformationSystemInfo> onCreateAsset;
  final ValueChanged<InformationAssetInfo> onEditAsset;
  final ValueChanged<InformationAssetInfo> onDeleteAsset;

  const _InventoryContent({
    required this.state,
    required this.working,
    required this.onCreateFunction,
    required this.onEditFunction,
    required this.onDeleteFunction,
    required this.onCreateSystem,
    required this.onEditSystem,
    required this.onDeleteSystem,
    required this.onImportSystemInventory,
    required this.onExportSystemInventory,
    required this.onCreateAsset,
    required this.onEditAsset,
    required this.onDeleteAsset,
  });

  @override
  Widget build(BuildContext context) {
    final inventory = state.inventory;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inventaire du périmètre IRN',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Espace : ${inventory.tenantDisplayName.isEmpty ? state.configuration.tenantId : inventory.tenantDisplayName}',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            '${inventory.criticalFunctions.length} fonction(s) critique(s)',
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${inventory.informationSystems.length} système(s) d’information',
                          ),
                        ),
                        Chip(
                          label: Text('${inventory.assets.length} actif(s)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: working ? null : onCreateFunction,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une fonction critique'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (inventory.criticalFunctions.isEmpty)
              const _EmptyInventoryCard()
            else
              for (final function in inventory.criticalFunctions) ...[
                _FunctionCard(
                  function: function,
                  systems: inventory.systemsForFunction(function.id),
                  inventory: inventory,
                  working: working,
                  onEditFunction: () => onEditFunction(function),
                  onDeleteFunction: () => onDeleteFunction(function),
                  onCreateSystem: () => onCreateSystem(function),
                  onEditSystem: onEditSystem,
                  onDeleteSystem: onDeleteSystem,
                  onImportSystemInventory: onImportSystemInventory,
                  onExportSystemInventory: onExportSystemInventory,
                  onCreateAsset: onCreateAsset,
                  onEditAsset: onEditAsset,
                  onDeleteAsset: onDeleteAsset,
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _FunctionCard extends StatelessWidget {
  final CriticalFunctionInfo function;
  final List<InformationSystemInfo> systems;
  final IrnAssetInventory inventory;
  final bool working;
  final VoidCallback onEditFunction;
  final VoidCallback onDeleteFunction;
  final VoidCallback onCreateSystem;
  final ValueChanged<InformationSystemInfo> onEditSystem;
  final ValueChanged<InformationSystemInfo> onDeleteSystem;
  final ValueChanged<InformationSystemInfo> onImportSystemInventory;
  final ValueChanged<InformationSystemInfo> onExportSystemInventory;
  final ValueChanged<InformationSystemInfo> onCreateAsset;
  final ValueChanged<InformationAssetInfo> onEditAsset;
  final ValueChanged<InformationAssetInfo> onDeleteAsset;

  const _FunctionCard({
    required this.function,
    required this.systems,
    required this.inventory,
    required this.working,
    required this.onEditFunction,
    required this.onDeleteFunction,
    required this.onCreateSystem,
    required this.onEditSystem,
    required this.onDeleteSystem,
    required this.onImportSystemInventory,
    required this.onExportSystemInventory,
    required this.onCreateAsset,
    required this.onEditAsset,
    required this.onDeleteAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(function.name),
        subtitle: Text(
          function.description.isEmpty
              ? '${systems.length} SI associé(s)'
              : '${systems.length} SI associé(s) — ${function.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: working ? null : onEditFunction,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: working ? null : onDeleteFunction,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: working ? null : onCreateSystem,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un SI'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (systems.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Aucun système d’information associé.'),
            )
          else
            for (final system in systems) ...[
              _SystemTile(
                system: system,
                assets: inventory.assetsForSystem(system.id),
                working: working,
                onEdit: () => onEditSystem(system),
                onDelete: () => onDeleteSystem(system),
                onImportAssets: () => onImportSystemInventory(system),
                onExportAssets: () => onExportSystemInventory(system),
                onCreateAsset: () => onCreateAsset(system),
                onEditAsset: onEditAsset,
                onDeleteAsset: onDeleteAsset,
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _SystemTile extends StatelessWidget {
  final InformationSystemInfo system;
  final List<InformationAssetInfo> assets;
  final bool working;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onImportAssets;
  final VoidCallback onExportAssets;
  final VoidCallback onCreateAsset;
  final ValueChanged<InformationAssetInfo> onEditAsset;
  final ValueChanged<InformationAssetInfo> onDeleteAsset;

  const _SystemTile({
    required this.system,
    required this.assets,
    required this.working,
    required this.onEdit,
    required this.onDelete,
    required this.onImportAssets,
    required this.onExportAssets,
    required this.onCreateAsset,
    required this.onEditAsset,
    required this.onDeleteAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ExpansionTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text(system.name),
        subtitle: Text(
          [
            if (system.owner.isNotEmpty) 'Porté par ${system.owner}',
            '${assets.length} actif(s)',
          ].join(' — '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (system.description.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(system.description),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: working ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              TextButton.icon(
                onPressed: working ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
              TextButton.icon(
                onPressed: working ? null : onImportAssets,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Importer Excel'),
              ),
              TextButton.icon(
                onPressed: working ? null : onExportAssets,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exporter Excel'),
              ),
              FilledButton.icon(
                onPressed: working ? null : onCreateAsset,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un actif'),
              ),
            ],
          ),
          if (assets.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Aucun actif associé.'),
            )
          else
            for (final asset in assets)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(asset.name),
                subtitle: Text(
                  [
                    if (asset.assetType.isNotEmpty) asset.assetType,
                    if (asset.description.isNotEmpty) asset.description,
                  ].join(' — '),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      onPressed: working ? null : () => onEditAsset(asset),
                      tooltip: 'Modifier l’actif',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: working ? null : () => onDeleteAsset(asset),
                      tooltip: 'Supprimer l’actif',
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
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

class _EmptyInventoryCard extends StatelessWidget {
  const _EmptyInventoryCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Aucune fonction critique n’est encore déclarée. Commence par ajouter une fonction critique, puis rattache un système d’information et ses actifs.',
        ),
      ),
    );
  }
}

class _FunctionFormResult {
  final String name;
  final String description;

  const _FunctionFormResult({required this.name, required this.description});
}

class _FunctionDialog extends StatefulWidget {
  final CriticalFunctionInfo? function;

  const _FunctionDialog({this.function});

  @override
  State<_FunctionDialog> createState() => _FunctionDialogState();
}

class _FunctionDialogState extends State<_FunctionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
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
            ? 'Modifier la fonction critique'
            : 'Ajouter une fonction critique',
      ),
      content: ResponsiveDialogContent(
        maxWidth: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: const InputDecoration(
                  labelText: 'Nom de la fonction critique',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom est obligatoire.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _SystemFormResult {
  final String functionId;
  final String name;
  final String description;
  final String owner;

  const _SystemFormResult({
    required this.functionId,
    required this.name,
    required this.description,
    required this.owner,
  });
}

class _SystemDialog extends StatefulWidget {
  final List<CriticalFunctionInfo> functions;
  final InformationSystemInfo? system;
  final String initialFunctionId;

  const _SystemDialog({
    required this.functions,
    this.system,
    this.initialFunctionId = '',
  });

  @override
  State<_SystemDialog> createState() => _SystemDialogState();
}

class _SystemDialogState extends State<_SystemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ownerController;
  late String _functionId;

  @override
  void initState() {
    super.initState();
    _functionId = widget.system?.functionId ?? widget.initialFunctionId;
    if (_functionId.isEmpty && widget.functions.isNotEmpty) {
      _functionId = widget.functions.first.id;
    }
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
        functionId: _functionId,
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
            ? 'Modifier le système d’information'
            : 'Ajouter un système d’information',
      ),
      content: ResponsiveDialogContent(
        maxWidth: 620,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _functionId.isEmpty ? null : _functionId,
                items: widget.functions
                    .map(
                      (function) => DropdownMenuItem<String>(
                        value: function.id,
                        child: Text(function.name),
                      ),
                    )
                    .toList(growable: false),
                decoration: const InputDecoration(
                  labelText: 'Fonction critique porteuse',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                validator: (value) => (value ?? '').isEmpty
                    ? 'La fonction critique est obligatoire.'
                    : null,
                onChanged: (value) => setState(() => _functionId = value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: const InputDecoration(
                  labelText: 'Nom du système d’information',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom est obligatoire.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerController,
                decoration: const InputDecoration(
                  labelText: 'Porteur / responsable',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _AssetFormResult {
  final String systemId;
  final String name;
  final String assetType;
  final String description;

  const _AssetFormResult({
    required this.systemId,
    required this.name,
    required this.assetType,
    required this.description,
  });
}

class _AssetDialog extends StatefulWidget {
  final List<InformationSystemInfo> systems;
  final InformationAssetInfo? asset;
  final String initialSystemId;

  const _AssetDialog({
    required this.systems,
    this.asset,
    this.initialSystemId = '',
  });

  @override
  State<_AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<_AssetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _descriptionController;
  late String _systemId;
  @override
  void initState() {
    super.initState();
    _systemId = widget.asset?.systemId ?? widget.initialSystemId;
    if (_systemId.isEmpty && widget.systems.isNotEmpty) {
      _systemId = widget.systems.first.id;
    }
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
        systemId: _systemId,
        name: _nameController.text.trim(),
        assetType: _typeController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.asset != null;
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(editing ? 'Modifier l’actif' : 'Ajouter un actif'),
      content: ResponsiveDialogContent(
        maxWidth: 620,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _systemId.isEmpty ? null : _systemId,
                items: widget.systems
                    .map(
                      (system) => DropdownMenuItem<String>(
                        value: system.id,
                        child: Text(system.name),
                      ),
                    )
                    .toList(growable: false),
                decoration: const InputDecoration(
                  labelText: 'Système d’information',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                validator: (value) => (value ?? '').isEmpty
                    ? 'Le système d’information est obligatoire.'
                    : null,
                onChanged: (value) => setState(() => _systemId = value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: const InputDecoration(
                  labelText: 'Nom de l’actif',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom est obligatoire.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _typeController,
                decoration: const InputDecoration(
                  labelText: 'Type d’actif',
                  hintText:
                      'Ex. application, base de données, service, infrastructure…',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
