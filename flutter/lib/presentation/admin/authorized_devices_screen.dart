import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/authorized_device.dart';
import '../../domain/models/device_enrollment_request.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class AuthorizedDevicesScreen extends StatefulWidget {
  final AppUser activeUser;

  const AuthorizedDevicesScreen({required this.activeUser, super.key});

  @override
  State<AuthorizedDevicesScreen> createState() =>
      _AuthorizedDevicesScreenState();
}

class _AuthorizedDevicesScreenState extends State<AuthorizedDevicesScreen> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _accessPolicy = const AccessPolicyService();

  late Future<_AuthorizedDevicesStateData> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = _loadDevices();
  }

  Future<_AuthorizedDevicesStateData> _loadDevices() async {
    if (!_accessPolicy.canManageTenantAuthorizedDevices(widget.activeUser)) {
      return _AuthorizedDevicesStateData(
        configuration: SyncConfiguration.empty(),
        devices: const <AuthorizedDevice>[],
        serverAvailable: false,
        title: OpenIrnLocalizations.instance.tr(
          'authorized_devices.error.access_denied.title',
          fallback: 'Accès refusé',
        ),
        message: OpenIrnLocalizations.instance.tr(
          'authorized_devices.error.access_denied.message',
          fallback:
              'La gestion des terminaux autorisés est réservée aux administrateurs et pilotes IRN.',
        ),
        includeAllTenants: false,
      );
    }
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _AuthorizedDevicesStateData(
        configuration: configuration,
        devices: const <AuthorizedDevice>[],
        serverAvailable: false,
        title: OpenIrnLocalizations.instance.tr(
          'authorized_devices.error.server_not_configured.title',
          fallback: 'Serveur non configuré',
        ),
        message: OpenIrnLocalizations.instance.tr(
          'authorized_devices.error.server_not_configured.message',
          fallback:
              'La synchronisation serveur n’est pas configurée sur ce terminal. Impossible de gérer les terminaux autorisés.',
        ),
        includeAllTenants: false,
      );
    }

    final includeAllTenants =
        widget.activeUser.role == AppUserRole.administrator;
    final result = await _apiClient.loadDevices(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      includeAllTenants: includeAllTenants,
    );

    return _AuthorizedDevicesStateData(
      configuration: configuration,
      devices: result.devices,
      enrollmentRequests: result.enrollmentRequests,
      includeAllTenants: includeAllTenants,
      serverAvailable: result.isAvailable,
      title: result.title,
      message: result.message,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadDevices();
    });
    await _future;
  }

  Future<void> _createEnrollment(_AuthorizedDevicesStateData state) async {
    if (!state.configuration.isConfigured || _working) {
      return;
    }

    final result = await showDialog<_EnrollmentFormResult>(
      context: context,
      builder: (context) => _EnrollmentDialog(activeUser: widget.activeUser),
    );
    if (result == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      final enrollment = await _apiClient.createDeviceEnrollment(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        createdByUserId: widget.activeUser.id,
        label: result.label,
        expiresInMinutes: result.expiresInMinutes,
      );

      if (!mounted) {
        return;
      }

      if (!enrollment.isAccepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${enrollment.title} — ${enrollment.message}'),
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => _EnrollmentCodeDialog(enrollment: enrollment),
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

  Future<void> _approveEnrollmentRequest(
    _AuthorizedDevicesStateData state,
    DeviceEnrollmentRequest request,
  ) async {
    if (!state.configuration.isConfigured || _working || !request.isPending) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      final enrollment = await _apiClient.approveDeviceEnrollmentRequest(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: request.tenantId,
        apiToken: state.configuration.apiToken,
        requestId: request.requestId,
        expiresInMinutes: 15,
      );

      if (!mounted) {
        return;
      }

      if (!enrollment.isAccepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${enrollment.title} — ${enrollment.message}'),
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => _EnrollmentCodeDialog(enrollment: enrollment),
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

  Future<void> _rejectEnrollmentRequest(
    _AuthorizedDevicesStateData state,
    DeviceEnrollmentRequest request,
  ) async {
    if (!state.configuration.isConfigured || _working || !request.isPending) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: Text(
          context.tr(
            'authorized_devices.reject_request.title',
            fallback: 'Refuser la demande ?',
          ),
        ),
        content: ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            context.tr(
              'authorized_devices.reject_request.message',
              fallback:
                  'La demande d’autorisation du terminal « {device} » sera marquée comme refusée.',
              values: {'device': request.displayName},
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.cancel', fallback: 'Annuler')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.block_outlined),
            label: Text(context.tr('common.reject', fallback: 'Refuser')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _runDeviceMutation(
      () => _apiClient.rejectDeviceEnrollmentRequest(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: request.tenantId,
        apiToken: state.configuration.apiToken,
        requestId: request.requestId,
      ),
    );
  }

  Future<void> _renameDevice(
    _AuthorizedDevicesStateData state,
    AuthorizedDevice device,
  ) async {
    if (!state.configuration.isConfigured || _working || !device.isActive) {
      return;
    }

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDeviceDialog(device: device),
    );
    if (newName == null || newName.trim().isEmpty) {
      return;
    }

    await _runDeviceMutation(
      () => _apiClient.renameDevice(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: device.tenantId.trim().isEmpty
            ? state.configuration.tenantId
            : device.tenantId,
        apiToken: state.configuration.apiToken,
        deviceId: device.deviceId,
        name: newName,
      ),
    );
  }

  Future<void> _revokeDevice(
    _AuthorizedDevicesStateData state,
    AuthorizedDevice device,
  ) async {
    if (!state.configuration.isConfigured || _working || !device.isActive) {
      return;
    }

    final isCurrentDevice = device.deviceId == state.configuration.deviceId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: Text(
          context.tr(
            'authorized_devices.revoke.title',
            fallback: 'Révoquer ce terminal ?',
          ),
        ),
        content: ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            context.tr(
              'authorized_devices.revoke.message',
              fallback:
                  'Le terminal « {device} » ne pourra plus utiliser son jeton OpenIRN. Cette opération est recommandée si le terminal est perdu, remplacé ou compromis.{currentWarning}',
              values: {
                'device': device.displayName,
                'currentWarning': isCurrentDevice
                    ? context.tr(
                        'authorized_devices.revoke.current_warning',
                        fallback:
                            '\n\nAttention : il s’agit du terminal courant. Son autorisation locale sera aussi supprimée après révocation.',
                      )
                    : '',
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.cancel', fallback: 'Annuler')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.block_outlined),
            label: Text(
              context.tr(
                'authorized_devices.action.revoke',
                fallback: 'Révoquer',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final success = await _runDeviceMutation(
      () => _apiClient.revokeDevice(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: device.tenantId.trim().isEmpty
            ? state.configuration.tenantId
            : device.tenantId,
        apiToken: state.configuration.apiToken,
        deviceId: device.deviceId,
      ),
    );

    if (success && isCurrentDevice) {
      final cleared =
          SyncConfiguration.empty(
            deviceId: state.configuration.deviceId,
          ).copyWith(
            tenantId: state.configuration.tenantId,
            enabled: false,
            apiToken: '',
          );
      await _configurationRepository.saveConfiguration(cleared);
      AppSyncCoordinator.instance.stop();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'authorized_devices.revoke.current_success',
              fallback:
                  'Terminal courant révoqué. Veuillez autoriser de nouveau ce terminal pour resynchroniser.',
            ),
          ),
        ),
      );
    }
  }

  Future<bool> _runDeviceMutation(
    Future<OpenIrnApiDevicesResult> Function() action,
  ) async {
    setState(() {
      _working = true;
    });

    try {
      final result = await action();
      if (!mounted) {
        return false;
      }
      if (!result.isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.title} — ${result.message}')),
        );
        return false;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      await _refresh();
      return true;
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Terminaux autorisés',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Actualiser',
            icon: Icons.refresh,
            enabled: !_working,
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_AuthorizedDevicesStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final state = snapshot.data;
          if (state == null) {
            return Center(
              child: Text(
                context.tr(
                  'authorized_devices.error.load_failed',
                  fallback: 'Impossible de charger les terminaux autorisés.',
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _HeaderCard(
                      state: state,
                      working: _working,
                      onCreateEnrollment: state.serverAvailable
                          ? () => _createEnrollment(state)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    if (state.serverAvailable &&
                        state.enrollmentRequests.isNotEmpty) ...[
                      _EnrollmentRequestsSection(
                        requests: state.enrollmentRequests,
                        working: _working,
                        onApprove: (request) =>
                            _approveEnrollmentRequest(state, request),
                        onReject: (request) =>
                            _rejectEnrollmentRequest(state, request),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!state.serverAvailable)
                      _MessageCard(
                        icon: Icons.warning_amber_outlined,
                        title: state.title,
                        message: state.message,
                      )
                    else if (state.devices.isEmpty)
                      _MessageCard(
                        icon: Icons.devices_other_outlined,
                        title: context.tr(
                          'authorized_devices.empty.title',
                          fallback: 'Aucun terminal enregistré',
                        ),
                        message: context.tr(
                          'authorized_devices.empty.message',
                          fallback:
                              'Créez une invitation pour autoriser le premier terminal avec un code individuel.',
                        ),
                      )
                    else
                      for (final device in state.devices) ...[
                        _DeviceCard(
                          device: device,
                          working: _working,
                          isCurrentDevice:
                              device.deviceId == state.configuration.deviceId,
                          onRename: () => _renameDevice(state, device),
                          onRevoke: () => _revokeDevice(state, device),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final _AuthorizedDevicesStateData state;
  final bool working;
  final VoidCallback? onCreateEnrollment;

  const _HeaderCard({
    required this.state,
    required this.working,
    required this.onCreateEnrollment,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = state.devices.where((device) => device.isActive).length;
    final revokedCount = state.devices.length - activeCount;
    final pendingRequestCount = state.enrollmentRequests
        .where((request) => request.isPending)
        .length;
    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.devices_outlined, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'authorized_devices.title',
                  fallback: 'Terminaux autorisés',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                state.serverAvailable
                    ? context.tr(
                        'authorized_devices.summary',
                        fallback:
                            '{active} actif(s), {revoked} révoqué(s), {pending} demande(s) en attente — {scope}',
                        values: {
                          'active': activeCount,
                          'revoked': revokedCount,
                          'pending': pendingRequestCount,
                          'scope': state.includeAllTenants
                              ? context.tr(
                                  'common.all_workspaces',
                                  fallback: 'tous les espaces',
                                )
                              : state.configuration.tenantLabel,
                        },
                      )
                    : state.message,
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
                    onPressed: working ? null : onCreateEnrollment,
                    icon: const Icon(Icons.add_link_outlined),
                    label: Text(
                      context.tr(
                        'authorized_devices.action.authorize_new',
                        fallback: 'Autoriser un nouveau terminal',
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: working ? null : onCreateEnrollment,
                    icon: const Icon(Icons.add_link_outlined),
                    label: Text(
                      context.tr(
                        'authorized_devices.action.authorize_new',
                        fallback: 'Autoriser un nouveau terminal',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final AuthorizedDevice device;
  final bool working;
  final bool isCurrentDevice;
  final VoidCallback onRename;
  final VoidCallback onRevoke;

  const _DeviceCard({
    required this.device,
    required this.working,
    required this.isCurrentDevice,
    required this.onRename,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final lastSeen = device.lastSeenAt == null
        ? context.tr(
            'authorized_devices.last_seen.never',
            fallback: 'Jamais vu',
          )
        : context.tr(
            'authorized_devices.last_seen.at',
            fallback: 'Dernière activité : {date}',
            values: {'date': _formatDateTime(device.lastSeenAt!)},
          );
    final statusColor = device.isActive
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.errorContainer;
    final statusTextColor = device.isActive
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onErrorContainer;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              device.isActive ? Icons.devices_outlined : Icons.block_outlined,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        device.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            context.trText(device.statusLabel),
                            style: TextStyle(color: statusTextColor),
                          ),
                        ),
                      ),
                      for (final workspace in device.effectiveWorkspaces)
                        Chip(
                          avatar: Icon(
                            workspace.isActive
                                ? Icons.account_tree_outlined
                                : Icons.block_outlined,
                            size: 18,
                          ),
                          label: Text(workspace.tenantLabel),
                        ),
                      if (isCurrentDevice)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Text(
                              context.tr(
                                'authorized_devices.current_device',
                                fallback: 'Ce terminal',
                              ),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${device.platformLabel} — $lastSeen'),
                  const SizedBox(height: 4),
                  Text(
                    device.workspaceCount > 1
                        ? context.tr(
                            'authorized_devices.enrolled.multiple',
                            fallback:
                                'Enrollé dans {count} espaces : {summary}',
                            values: {
                              'count': device.workspaceCount,
                              'summary': device.workspaceSummary,
                            },
                          )
                        : context.tr(
                            'authorized_devices.enrolled.single',
                            fallback: 'Enrollé dans {summary}',
                            values: {'summary': device.workspaceSummary},
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'authorized_devices.device_id',
                      fallback: 'Identifiant terminal : {deviceId}',
                      values: {'deviceId': device.deviceId},
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'authorized_devices.created_at',
                      fallback: 'Créé le {date}',
                      values: {'date': _formatDateTime(device.createdAt)},
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (device.revokedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        'authorized_devices.revoked_at',
                        fallback: 'Révoqué le {date}',
                        values: {'date': _formatDateTime(device.revokedAt)},
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: !working,
              onSelected: (value) {
                if (value == 'rename') {
                  onRename();
                } else if (value == 'revoke') {
                  onRevoke();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'rename',
                  enabled: device.isActive,
                  child: Text(
                    context.tr(
                      'authorized_devices.action.rename',
                      fallback: 'Renommer',
                    ),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'revoke',
                  enabled: device.isActive,
                  child: Text(
                    device.workspaceCount > 1
                        ? context.tr(
                            'authorized_devices.action.revoke_workspace',
                            fallback: 'Révoquer dans cet espace',
                          )
                        : context.tr(
                            'authorized_devices.action.revoke',
                            fallback: 'Révoquer',
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

class _EnrollmentRequestsSection extends StatelessWidget {
  final List<DeviceEnrollmentRequest> requests;
  final bool working;
  final ValueChanged<DeviceEnrollmentRequest> onApprove;
  final ValueChanged<DeviceEnrollmentRequest> onReject;

  const _EnrollmentRequestsSection({
    required this.requests,
    required this.working,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final pending = requests.where((request) => request.isPending).toList();
    final history = requests.where((request) => !request.isPending).take(5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notification_important_outlined, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'authorized_devices.requests.title',
                          fallback: 'Demandes d’enrôlement',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pending.isEmpty
                            ? context.tr(
                                'authorized_devices.requests.none_pending',
                                fallback: 'Aucune demande en attente.',
                              )
                            : context.tr(
                                'authorized_devices.requests.pending_count',
                                fallback:
                                    '{count} demande(s) en attente de validation.',
                                values: {'count': pending.length},
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final request in pending) ...[
          _EnrollmentRequestCard(
            request: request,
            working: working,
            onApprove: () => onApprove(request),
            onReject: () => onReject(request),
          ),
          const SizedBox(height: 12),
        ],
        for (final request in history) ...[
          _EnrollmentRequestCard(
            request: request,
            working: working,
            onApprove: () => onApprove(request),
            onReject: () => onReject(request),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _EnrollmentRequestCard extends StatelessWidget {
  final DeviceEnrollmentRequest request;
  final bool working;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _EnrollmentRequestCard({
    required this.request,
    required this.working,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = request.isPending
        ? colorScheme.tertiaryContainer
        : colorScheme.surfaceContainerHighest;
    final statusTextColor = request.isPending
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              request.isPending
                  ? Icons.phonelink_lock_outlined
                  : Icons.phonelink_setup_outlined,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        request.displayName,
                        style: theme.textTheme.titleMedium,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            context.trText(request.statusLabel),
                            style: TextStyle(color: statusTextColor),
                          ),
                        ),
                      ),
                      if (request.tenantId.trim().isNotEmpty)
                        Chip(
                          avatar: const Icon(
                            Icons.account_tree_outlined,
                            size: 18,
                          ),
                          label: Text(request.tenantLabel),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'authorized_devices.requests.requested_at',
                      fallback: '{platform} — demandée le {date}',
                      values: {
                        'platform': request.platformLabel,
                        'date': _formatDateTime(request.requestedAt),
                      },
                    ),
                  ),
                  if (request.requesterNote.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      request.requesterNote,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (request.decidedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'authorized_devices.requests.decided_at',
                        fallback: 'Traitée le {date}',
                        values: {'date': _formatDateTime(request.decidedAt)},
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (request.isPending)
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: working ? null : onReject,
                    icon: const Icon(Icons.block_outlined),
                    label: Text(
                      context.tr('common.reject', fallback: 'Refuser'),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: working ? null : onApprove,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      context.tr('common.approve', fallback: 'Approuver'),
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

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
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
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnrollmentDialog extends StatefulWidget {
  final AppUser activeUser;

  const _EnrollmentDialog({required this.activeUser});

  @override
  State<_EnrollmentDialog> createState() => _EnrollmentDialogState();
}

class _EnrollmentDialogState extends State<_EnrollmentDialog> {
  late final TextEditingController _labelController;
  int _expiresInMinutes = 10;

  @override
  void initState() {
    super.initState();
    final userName = widget.activeUser.fullName.isNotEmpty
        ? widget.activeUser.fullName
        : widget.activeUser.id;
    _labelController = TextEditingController(
      text: OpenIrnLocalizations.instance.tr(
        'authorized_devices.enrollment.default_label',
        fallback: 'Invitation créée par {user}',
        values: {'user': userName},
      ),
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'authorized_devices.enrollment.title',
          fallback: 'Autoriser un nouveau terminal',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'authorized_devices.enrollment.help',
                  fallback:
                      'OpenIRN va générer un code court à usage unique. Le nouveau terminal devra saisir ce code avant expiration.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelController,
                autofocus: shouldAutofocusTextField(context),
                decoration: InputDecoration(
                  labelText: context.tr(
                    'authorized_devices.enrollment.label',
                    fallback: 'Libellé interne',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _expiresInMinutes,
                decoration: InputDecoration(
                  labelText: context.tr(
                    'authorized_devices.enrollment.validity',
                    fallback: 'Durée de validité',
                  ),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 5,
                    child: Text(
                      context.tr(
                        'common.minutes',
                        fallback: '{count} minutes',
                        values: {'count': 5},
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 10,
                    child: Text(
                      context.tr(
                        'common.minutes',
                        fallback: '{count} minutes',
                        values: {'count': 10},
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 15,
                    child: Text(
                      context.tr(
                        'common.minutes',
                        fallback: '{count} minutes',
                        values: {'count': 15},
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _expiresInMinutes = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.cancel', fallback: 'Annuler')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            _EnrollmentFormResult(
              label: _labelController.text.trim(),
              expiresInMinutes: _expiresInMinutes,
            ),
          ),
          icon: const Icon(Icons.add_link_outlined),
          label: Text(
            context.tr(
              'authorized_devices.enrollment.create_code',
              fallback: 'Créer le code',
            ),
          ),
        ),
      ],
    );
  }
}

class _EnrollmentCodeDialog extends StatelessWidget {
  final OpenIrnApiEnrollmentResult enrollment;

  const _EnrollmentCodeDialog({required this.enrollment});

  @override
  Widget build(BuildContext context) {
    final expiresAt = enrollment.expiresAt == null
        ? context.tr(
            'authorized_devices.enrollment.no_expiration',
            fallback: 'Expiration non précisée',
          )
        : context.tr(
            'authorized_devices.enrollment.expires_at',
            fallback: 'Expire le {date}',
            values: {'date': _formatDateTime(enrollment.expiresAt)},
          );

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'authorized_devices.enrollment.code_title',
          fallback: 'Code d’appairage',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'authorized_devices.enrollment.code_help',
                fallback:
                    'Sur le nouveau terminal, ouvrez OpenIRN puis choisissez « Autoriser ce terminal ». Saisissez ensuite le code ci-dessous.',
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                enrollment.code,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(expiresAt),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'authorized_devices.enrollment.one_time_code',
                fallback:
                    'Ce code est à usage unique. Il ne sera plus affiché après fermeture de cette fenêtre.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: enrollment.code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.tr(
                      'authorized_devices.enrollment.code_copied',
                      fallback: 'Code copié.',
                    ),
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: Text(context.tr('common.copy', fallback: 'Copier')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.close', fallback: 'Fermer')),
        ),
      ],
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  final AuthorizedDevice device;

  const _RenameDeviceDialog({required this.device});

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.device.displayName);
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
          'authorized_devices.rename.title',
          fallback: 'Renommer le terminal',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 620,
        child: TextField(
          controller: _controller,
          autofocus: shouldAutofocusTextField(context),
          decoration: InputDecoration(
            labelText: context.tr(
              'authorized_devices.rename.label',
              fallback: 'Nom du terminal',
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(context),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.cancel', fallback: 'Annuler')),
        ),
        FilledButton(
          onPressed: () => _submit(context),
          child: Text(
            context.tr(
              'authorized_devices.action.rename',
              fallback: 'Renommer',
            ),
          ),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    Navigator.of(context).pop(value);
  }
}

class _AuthorizedDevicesStateData {
  final SyncConfiguration configuration;
  final List<AuthorizedDevice> devices;
  final List<DeviceEnrollmentRequest> enrollmentRequests;
  final bool includeAllTenants;
  final bool serverAvailable;
  final String title;
  final String message;

  const _AuthorizedDevicesStateData({
    required this.configuration,
    required this.devices,
    this.enrollmentRequests = const <DeviceEnrollmentRequest>[],
    required this.includeAllTenants,
    required this.serverAvailable,
    required this.title,
    required this.message,
  });
}

class _EnrollmentFormResult {
  final String label;
  final int expiresInMinutes;

  const _EnrollmentFormResult({
    required this.label,
    required this.expiresInMinutes,
  });
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'date inconnue';
  }
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
