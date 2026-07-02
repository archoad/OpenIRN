import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/models/tenant_info.dart';
import '../../domain/services/app_session_manager.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class TenantManagementScreen extends StatefulWidget {
  final AppUser activeUser;

  const TenantManagementScreen({required this.activeUser, super.key});

  @override
  State<TenantManagementScreen> createState() => _TenantManagementScreenState();
}

class _TenantManagementScreenState extends State<TenantManagementScreen> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  late Future<_TenantManagementStateData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadTenants();
  }

  Future<_TenantManagementStateData> _loadTenants() async {
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _TenantManagementStateData(
        configuration: configuration,
        title: 'Terminal non autorisé',
        message:
            'Veuillez autoriser ce terminal avant de gérer les espaces de travail.',
        tenants: const <TenantInfo>[],
        solutionAdministrator: false,
      );
    }

    final result = await _apiClient.loadTenants(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    return _TenantManagementStateData(
      configuration: configuration,
      title: result.title,
      message: result.message,
      tenants: result.tenants,
      solutionAdministrator: result.solutionAdministrator,
    );
  }

  void _reload() {
    setState(() {
      _future = _loadTenants();
    });
  }

  Future<void> _createTenant(_TenantManagementStateData state) async {
    final form = await showDialog<_TenantCreateFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TenantCreateDialog(),
    );
    if (form == null || !mounted) {
      return;
    }

    final result = await _apiClient.createTenant(
      baseUrl: state.configuration.apiBaseUrl,
      requesterTenantId: state.configuration.tenantId,
      tenantId: form.tenantId,
      displayName: form.displayName,
      description: form.description,
      pilotFirstName: form.pilotFirstName,
      pilotLastName: form.pilotLastName,
      pilotEmail: form.pilotEmail,
      pilotPin: form.pilotPin,
      apiToken: state.configuration.apiToken,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title} — ${result.message}')),
    );

    if (result.isAvailable) {
      _reload();
    }
  }

  Future<void> _renameTenant(
    _TenantManagementStateData state,
    TenantInfo tenant,
  ) async {
    final form = await showDialog<_TenantRenameFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TenantRenameDialog(tenant: tenant),
    );
    if (form == null || !mounted) {
      return;
    }

    final result = await _apiClient.updateTenant(
      baseUrl: state.configuration.apiBaseUrl,
      tenantId: tenant.id,
      displayName: form.displayName,
      apiToken: state.configuration.apiToken,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title} — ${result.message}')),
    );

    if (result.isAvailable) {
      _reload();
    }
  }

  Future<void> _switchTenant(
    TenantInfo tenant, {
    required bool solutionAdministrator,
  }) async {
    final configuration = await _configurationRepository.loadConfiguration();
    if (solutionAdministrator) {
      await _configurationRepository
          .saveTenantSelectionForSolutionAdministration(
            configuration.copyWith(tenantId: tenant.id, enabled: true),
          );
    } else {
      await _configurationRepository.saveConfiguration(
        configuration.copyWith(tenantId: tenant.id, apiToken: ''),
      );
      AppSessionManager.instance.clearSession(
        reason:
            'Espace de travail changé : veuillez ouvrir une session dans ${tenant.displayName}.',
      );
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          solutionAdministrator
              ? 'Espace administré : ${tenant.displayName}. La session d’administration globale reste active.'
              : 'Espace sélectionné : ${tenant.displayName}. Veuillez déverrouiller la session pour continuer.',
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Espaces de travail'),
      body: FutureBuilder<_TenantManagementStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = snapshot.data;
          if (state == null) {
            return const Center(
              child: Text('État de l’espace de travail indisponible.'),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TenantIntroCard(
                    state: state,
                    onCreateTenant: () => _createTenant(state),
                  ),
                  const SizedBox(height: 12),
                  for (final tenant in state.tenants) ...[
                    _TenantCard(
                      tenant: tenant,
                      isCurrent: tenant.id == state.configuration.tenantId,
                      solutionAdministrator: state.solutionAdministrator,
                      onRename: () => _renameTenant(state, tenant),
                      onSwitch: tenant.id == state.configuration.tenantId
                          ? null
                          : () => _switchTenant(
                              tenant,
                              solutionAdministrator:
                                  state.solutionAdministrator,
                            ),
                    ),
                    const SizedBox(height: 12),
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

class _TenantManagementStateData {
  final SyncConfiguration configuration;
  final String title;
  final String message;
  final List<TenantInfo> tenants;
  final bool solutionAdministrator;

  const _TenantManagementStateData({
    required this.configuration,
    required this.title,
    required this.message,
    required this.tenants,
    required this.solutionAdministrator,
  });
}

class _TenantIntroCard extends StatelessWidget {
  final _TenantManagementStateData state;
  final VoidCallback onCreateTenant;

  const _TenantIntroCard({required this.state, required this.onCreateTenant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.account_tree_outlined, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestion des espaces de travail',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(state.message),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${state.tenants.length} espace(s)')),
                  Chip(
                    label: Text(
                      'Espace actif : ${state.configuration.tenantId}',
                    ),
                  ),
                  const Chip(label: Text('Espace par défaut permanent')),
                  if (state.solutionAdministrator)
                    const Chip(label: Text('Administrateur solution')),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onCreateTenant,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Créer un espace'),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: onCreateTenant,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Créer un espace'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  final TenantInfo tenant;
  final bool isCurrent;
  final bool solutionAdministrator;
  final VoidCallback onRename;
  final VoidCallback? onSwitch;

  const _TenantCard({
    required this.tenant,
    required this.isCurrent,
    required this.solutionAdministrator,
    required this.onRename,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          tenant.isDefault ? Icons.home_work_outlined : Icons.business_outlined,
          size: 34,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tenant.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(tenant.id),
              if (tenant.description.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tenant.description),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isCurrent) const Chip(label: Text('Espace actif')),
                  if (tenant.permanent) const Chip(label: Text('Permanent')),
                  Chip(
                    label: Text(
                      '${tenant.activeUserCount} utilisateur(s) actif(s)',
                    ),
                  ),
                  Chip(
                    label: Text(
                      '${tenant.administratorCount} administrateur(s)',
                    ),
                  ),
                  Chip(label: Text('${tenant.pilotCount} pilote(s)')),
                  Chip(label: Text('${tenant.campaignCount} campagne(s)')),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onRename,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Renommer'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSwitch,
                        icon: const Icon(Icons.login_outlined),
                        label: Text(
                          solutionAdministrator
                              ? 'Administrer cet espace'
                              : 'Utiliser cet espace',
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onRename,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Renommer'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSwitch,
                        icon: const Icon(Icons.login_outlined),
                        label: Text(
                          solutionAdministrator
                              ? 'Administrer cet espace'
                              : 'Utiliser cet espace',
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

class _TenantRenameFormResult {
  final String displayName;

  const _TenantRenameFormResult({required this.displayName});
}

class _TenantRenameDialog extends StatefulWidget {
  final TenantInfo tenant;

  const _TenantRenameDialog({required this.tenant});

  @override
  State<_TenantRenameDialog> createState() => _TenantRenameDialogState();
}

class _TenantRenameDialogState extends State<_TenantRenameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.tenant.displayName,
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _TenantRenameFormResult(
        displayName: _displayNameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Renommer l’espace de travail'),
      content: ResponsiveDialogContent(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('Identifiant : ${widget.tenant.id}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayNameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: const InputDecoration(
                  labelText: 'Nouveau nom affiché',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) {
                    return 'Le nom affiché est obligatoire.';
                  }
                  if (raw.length > 160) {
                    return 'Le nom ne doit pas dépasser 160 caractères.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
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
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _TenantCreateFormResult {
  final String tenantId;
  final String displayName;
  final String description;
  final String pilotFirstName;
  final String pilotLastName;
  final String pilotEmail;
  final String pilotPin;

  const _TenantCreateFormResult({
    required this.tenantId,
    required this.displayName,
    required this.description,
    required this.pilotFirstName,
    required this.pilotLastName,
    required this.pilotEmail,
    required this.pilotPin,
  });
}

class _TenantCreateDialog extends StatefulWidget {
  const _TenantCreateDialog();

  @override
  State<_TenantCreateDialog> createState() => _TenantCreateDialogState();
}

class _TenantCreateDialogState extends State<_TenantCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _tenantIdController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pilotFirstNameController = TextEditingController();
  final _pilotLastNameController = TextEditingController();
  final _pilotEmailController = TextEditingController();
  final _pilotPinController = TextEditingController();

  @override
  void dispose() {
    _tenantIdController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _pilotFirstNameController.dispose();
    _pilotLastNameController.dispose();
    _pilotEmailController.dispose();
    _pilotPinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _TenantCreateFormResult(
        tenantId: _tenantIdController.text.trim(),
        displayName: _displayNameController.text.trim(),
        description: _descriptionController.text.trim(),
        pilotFirstName: _pilotFirstNameController.text.trim(),
        pilotLastName: _pilotLastNameController.text.trim(),
        pilotEmail: _pilotEmailController.text.trim(),
        pilotPin: _pilotPinController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Créer un espace de travail'),
      content: ResponsiveDialogContent(
        maxWidth: 640,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _tenantIdController,
                  autofocus: shouldAutofocusTextField(context),
                  decoration: const InputDecoration(
                    labelText: 'Identifiant technique',
                    helperText:
                        'Lettres, chiffres, tiret, point ou soulignement. Exemple : filiale-a',
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) {
                      return 'L’identifiant de l’espace est obligatoire.';
                    }
                    if (raw == 'default') {
                      return 'L’espace default existe déjà et reste permanent.';
                    }
                    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(raw)) {
                      return 'Veuillez utiliser uniquement lettres, chiffres, tiret, point ou soulignement.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom affiché',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Pilote IRN initial',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotFirstNameController,
                  decoration: const InputDecoration(
                    labelText: 'Prénom',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotLastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotEmailController,
                  keyboardType: safeKeyboardType(
                    context,
                    TextInputType.emailAddress,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Email du pilote',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) {
                      return 'L’email du pilote est obligatoire.';
                    }
                    if (!raw.contains('@')) {
                      return 'Email invalide.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotPinController,
                  obscureText: true,
                  keyboardType: safeKeyboardType(context, TextInputType.number),
                  decoration: const InputDecoration(
                    labelText: 'Code personnel initial',
                    helperText:
                        '4 à 32 caractères. À transmettre au pilote IRN.',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.length < 4 || raw.length > 32) {
                      return 'Le code doit contenir entre 4 et 32 caractères.';
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
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Créer'),
        ),
      ],
    );
  }
}
