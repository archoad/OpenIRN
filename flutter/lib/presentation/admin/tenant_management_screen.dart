import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/models/tenant_info.dart';
import '../../domain/services/app_session_manager.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

String _localizedText(BuildContext context, String text) {
  return context.tr(text, fallback: context.trText(text));
}

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
        title: 'tenant.source.terminal_not_authorized',
        message: 'tenant.source.authorize_terminal_first',
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

  Future<void> _deleteTenant(_TenantManagementStateData state) async {
    final deletableTenants = state.tenants
        .where((tenant) => !tenant.permanent && !tenant.isDefault)
        .toList(growable: false);
    if (deletableTenants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tenant.delete.none_available'))),
      );
      return;
    }

    final selectedTenant = await showDialog<TenantInfo>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _TenantDeleteSelectionDialog(tenants: deletableTenants),
    );
    if (selectedTenant == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TenantDeleteConfirmationDialog(tenant: selectedTenant),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final result = await _apiClient.deleteTenant(
      baseUrl: state.configuration.apiBaseUrl,
      tenantId: selectedTenant.id,
      apiToken: state.configuration.apiToken,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title} — ${result.message}')),
    );

    if (result.isAvailable) {
      if (selectedTenant.id == state.configuration.tenantId) {
        TenantInfo? fallbackTenant;
        for (final tenant in result.tenants) {
          if (tenant.permanent) {
            fallbackTenant = tenant;
            break;
          }
        }
        if (fallbackTenant != null) {
          await _configurationRepository
              .saveTenantSelectionForSolutionAdministration(
                state.configuration.copyWith(
                  tenantId: fallbackTenant.id,
                  tenantDisplayName: fallbackTenant.label,
                  enabled: true,
                ),
              );
          if (!mounted) {
            return;
          }
        }
      }
      _reload();
    }
  }

  Future<void> _switchTenant(
    TenantInfo tenant, {
    required bool solutionAdministrator,
  }) async {
    final sessionReason = context.tr(
      'tenant.switch.session_reason',
      values: {'tenant': tenant.label},
    );
    final administeredMessage = context.tr(
      'tenant.switch.administered',
      values: {'tenant': tenant.label},
    );
    final selectedMessage = context.tr(
      'tenant.switch.selected',
      values: {'tenant': tenant.label},
    );
    final configuration = await _configurationRepository.loadConfiguration();
    if (solutionAdministrator) {
      await _configurationRepository
          .saveTenantSelectionForSolutionAdministration(
            configuration.copyWith(
              tenantId: tenant.id,
              tenantDisplayName: tenant.label,
              enabled: true,
            ),
          );
    } else {
      await _configurationRepository.saveConfiguration(
        configuration.copyWith(
          tenantId: tenant.id,
          tenantDisplayName: tenant.label,
          apiToken: '',
        ),
      );
      AppSessionManager.instance.clearSession(reason: sessionReason);
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          solutionAdministrator ? administeredMessage : selectedMessage,
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(title: context.tr('tenant.title')),
      body: FutureBuilder<_TenantManagementStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = snapshot.data;
          if (state == null) {
            return Center(child: Text(context.tr('tenant.state.unavailable')));
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
                    onDeleteTenant: () => _deleteTenant(state),
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
  final VoidCallback onDeleteTenant;

  const _TenantIntroCard({
    required this.state,
    required this.onCreateTenant,
    required this.onDeleteTenant,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final canDeleteTenant =
        state.solutionAdministrator &&
        state.tenants.any((tenant) => !tenant.permanent && !tenant.isDefault);
    final deleteButton = FilledButton.icon(
      onPressed: canDeleteTenant ? onDeleteTenant : null,
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.error,
        disabledBackgroundColor: theme.colorScheme.error.withValues(
          alpha: 0.24,
        ),
        foregroundColor: theme.colorScheme.onError,
        disabledForegroundColor: theme.colorScheme.onError.withValues(
          alpha: 0.54,
        ),
      ),
      icon: const Icon(Icons.delete_forever_outlined),
      label: Text(context.tr('tenant.action.delete_workspace')),
    );
    final createButton = FilledButton.icon(
      onPressed: onCreateTenant,
      icon: const Icon(Icons.add_business_outlined),
      label: Text(context.tr('tenant.action.create_workspace')),
    );
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
                context.tr('tenant.intro.title'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(_localizedText(context, state.message)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      context.tr(
                        'tenant.chip.workspace_count',
                        values: {'count': state.tenants.length},
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'tenant.chip.active_workspace',
                        values: {'tenant': state.configuration.tenantLabel},
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(context.tr('tenant.chip.default_permanent')),
                  ),
                  if (state.solutionAdministrator)
                    Chip(label: Text(context.tr('tenant.chip.solution_admin'))),
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
                  createButton,
                  const SizedBox(height: 8),
                  deleteButton,
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 240,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        createButton,
                        const SizedBox(height: 8),
                        deleteButton,
                      ],
                    ),
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
                tenant.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (tenant.description.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tenant.description),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isCurrent)
                    Chip(label: Text(context.tr('tenant.chip.current'))),
                  if (tenant.permanent)
                    Chip(label: Text(context.tr('tenant.chip.permanent'))),
                  Chip(
                    label: Text(
                      context.tr(
                        'tenant.chip.active_users',
                        values: {'count': tenant.activeUserCount},
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'tenant.chip.admin_count',
                        values: {'count': tenant.administratorCount},
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'tenant.chip.pilot_count',
                        values: {'count': tenant.pilotCount},
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'tenant.chip.campaign_count',
                        values: {'count': tenant.campaignCount},
                      ),
                    ),
                  ),
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
                        label: Text(context.tr('tenant.action.rename')),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSwitch,
                        icon: const Icon(Icons.login_outlined),
                        label: Text(
                          solutionAdministrator
                              ? context.tr('tenant.action.administer_workspace')
                              : context.tr('tenant.action.use_workspace'),
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
                        label: Text(context.tr('tenant.action.rename')),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSwitch,
                        icon: const Icon(Icons.login_outlined),
                        label: Text(
                          solutionAdministrator
                              ? context.tr('tenant.action.administer_workspace')
                              : context.tr('tenant.action.use_workspace'),
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

class _TenantDeleteSelectionDialog extends StatelessWidget {
  final List<TenantInfo> tenants;

  const _TenantDeleteSelectionDialog({required this.tenants});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(context.tr('tenant.delete.select_title')),
      content: ResponsiveDialogContent(
        maxWidth: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('tenant.delete.select_body')),
            const SizedBox(height: 12),
            for (final tenant in tenants)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(tenant.label),
                  subtitle: Text(
                    context.tr(
                      'tenant.delete.summary',
                      values: {
                        'users': tenant.activeUserCount,
                        'campaigns': tenant.campaignCount,
                      },
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(tenant),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel')),
        ),
      ],
    );
  }
}

class _TenantDeleteConfirmationDialog extends StatelessWidget {
  final TenantInfo tenant;

  const _TenantDeleteConfirmationDialog({required this.tenant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: Text(context.tr('tenant.delete.confirm_title')),
      content: ResponsiveDialogContent(
        maxWidth: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'tenant.delete.confirm_body',
                values: {'tenant': tenant.label},
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('tenant.delete.confirm_warning'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    context.tr(
                      'tenant.chip.active_users',
                      values: {'count': tenant.activeUserCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'tenant.chip.campaign_count',
                      values: {'count': tenant.campaignCount},
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('common.action.cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(context.tr('tenant.action.delete_permanently')),
        ),
      ],
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
    _displayNameController = TextEditingController(text: widget.tenant.label);
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
      _TenantRenameFormResult(displayName: _displayNameController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(context.tr('tenant.rename.title')),
      content: ResponsiveDialogContent(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _displayNameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: InputDecoration(
                  labelText: context.tr('tenant.field.new_display_name'),
                  prefixIcon: const Icon(Icons.business_outlined),
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) {
                    return context.tr(
                      'tenant.validation.display_name_required',
                    );
                  }
                  if (raw.length > 160) {
                    return context.tr(
                      'tenant.validation.display_name_too_long',
                    );
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
          child: Text(context.tr('common.action.cancel')),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(context.tr('common.action.save')),
        ),
      ],
    );
  }
}

class _TenantCreateFormResult {
  final String displayName;
  final String description;
  final String pilotFirstName;
  final String pilotLastName;
  final String pilotEmail;
  final String pilotPin;

  const _TenantCreateFormResult({
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
  final _displayNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pilotFirstNameController = TextEditingController();
  final _pilotLastNameController = TextEditingController();
  final _pilotEmailController = TextEditingController();
  final _pilotPinController = TextEditingController();

  @override
  void dispose() {
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
      title: Text(context.tr('tenant.create.title')),
      content: ResponsiveDialogContent(
        maxWidth: 640,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('tenant.create.uuid_hint'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  autofocus: shouldAutofocusTextField(context),
                  decoration: InputDecoration(
                    labelText: context.tr('tenant.field.display_name'),
                    prefixIcon: const Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: context.tr('common.field.description'),
                    prefixIcon: const Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('tenant.create.initial_pilot'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotFirstNameController,
                  decoration: InputDecoration(
                    labelText: context.tr('users.field.first_name'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotLastNameController,
                  decoration: InputDecoration(
                    labelText: context.tr('users.field.last_name'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotEmailController,
                  keyboardType: safeKeyboardType(
                    context,
                    TextInputType.emailAddress,
                  ),
                  decoration: InputDecoration(
                    labelText: context.tr('tenant.field.pilot_email'),
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) {
                      return context.tr(
                        'tenant.validation.pilot_email_required',
                      );
                    }
                    if (!raw.contains('@')) {
                      return context.tr('users.validation.email_invalid');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilotPinController,
                  obscureText: true,
                  keyboardType: safeKeyboardType(context, TextInputType.number),
                  decoration: InputDecoration(
                    labelText: context.tr('tenant.field.initial_pin'),
                    helperText: context.tr('tenant.field.initial_pin_helper'),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.length < 4 || raw.length > 32) {
                      return context.tr('tenant.validation.initial_pin_length');
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
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_business_outlined),
          label: Text(context.tr('common.action.create')),
        ),
      ],
    );
  }
}
