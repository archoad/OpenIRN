import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/authorized_device.dart';
import '../../domain/models/authorized_terminal_overview.dart';
import '../../domain/models/device_enrollment_request.dart';
import '../../domain/models/device_enrollment_invitation.dart';
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
        enrollmentInvitations: const <DeviceEnrollmentInvitation>[],
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
        enrollmentInvitations: const <DeviceEnrollmentInvitation>[],
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
      enrollmentInvitations: result.enrollmentInvitations,
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
        reusable: result.reusable,
        maxActiveDevices: result.maxActiveDevices,
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
        builder: (context) => _EnrollmentCodeDialog(
          enrollment: enrollment,
          requesterEmail: request.requesterEmail,
          onSendEmail: () => _apiClient.sendDeviceEnrollmentCodeEmail(
            baseUrl: state.configuration.apiBaseUrl,
            tenantId: request.tenantId,
            apiToken: state.configuration.apiToken,
            requestId: request.requestId,
            enrollmentId: enrollment.enrollmentId,
            code: enrollment.code,
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
      await _configurationRepository.clearDeviceAuthorization();
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

  Future<void> _revokeEnrollmentInvitation(
    _AuthorizedDevicesStateData state,
    DeviceEnrollmentInvitation invitation,
  ) async {
    if (_working || !invitation.isActive) {
      return;
    }
    final revokeDevices = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _RevokeEnrollmentInvitationDialog(invitation: invitation),
    );
    if (revokeDevices == null) {
      return;
    }

    OpenIrnApiDevicesResult? mutationResult;
    final success = await _runDeviceMutation(() async {
      mutationResult = await _apiClient.revokeReusableEnrollment(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: invitation.tenantId.trim().isEmpty
            ? state.configuration.tenantId
            : invitation.tenantId,
        apiToken: state.configuration.apiToken,
        enrollmentId: invitation.enrollmentId,
        revokeDevices: revokeDevices,
      );
      return mutationResult!;
    });
    if (!success || !revokeDevices) {
      return;
    }

    final rawRevokedIds = mutationResult?.responseBody?['revokedDeviceIds'];
    final revokedDeviceIds = rawRevokedIds is List
        ? rawRevokedIds.map((value) => value.toString()).toSet()
        : const <String>{};
    if (!revokedDeviceIds.contains(state.configuration.deviceId)) {
      return;
    }

    await _configurationRepository.clearDeviceAuthorization();
    AppSyncCoordinator.instance.stop();
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

          final terminalOverviews = AuthorizedTerminalOverview.combine(
            devices: state.devices,
            requests: state.enrollmentRequests,
          );

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
                        state.enrollmentInvitations.isNotEmpty) ...[
                      _ReusableEnrollmentInvitationsSection(
                        invitations: state.enrollmentInvitations,
                        working: _working,
                        canRevoke:
                            widget.activeUser.role == AppUserRole.administrator,
                        onRevoke: (invitation) =>
                            _revokeEnrollmentInvitation(state, invitation),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!state.serverAvailable)
                      _MessageCard(
                        icon: Icons.warning_amber_outlined,
                        title: state.title,
                        message: state.message,
                      )
                    else if (terminalOverviews.isEmpty)
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
                      for (final overview in terminalOverviews) ...[
                        AuthorizedTerminalCard(
                          device: overview.device,
                          request: overview.request,
                          requestCount: overview.requestCount,
                          working: _working,
                          isCurrentDevice:
                              overview.device?.deviceId ==
                              state.configuration.deviceId,
                          onApprove: overview.request?.isPending == true
                              ? () => _approveEnrollmentRequest(
                                  state,
                                  overview.request!,
                                )
                              : null,
                          onReject: overview.request?.isPending == true
                              ? () => _rejectEnrollmentRequest(
                                  state,
                                  overview.request!,
                                )
                              : null,
                          onRename: overview.device?.isActive == true
                              ? () => _renameDevice(state, overview.device!)
                              : null,
                          onRevoke: overview.device?.isActive == true
                              ? () => _revokeDevice(state, overview.device!)
                              : null,
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

class AuthorizedTerminalCard extends StatelessWidget {
  final AuthorizedDevice? device;
  final DeviceEnrollmentRequest? request;
  final int requestCount;
  final bool working;
  final bool isCurrentDevice;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onRename;
  final VoidCallback? onRevoke;

  const AuthorizedTerminalCard({
    required this.device,
    required this.request,
    this.requestCount = 0,
    required this.working,
    required this.isCurrentDevice,
    this.onApprove,
    this.onReject,
    this.onRename,
    this.onRevoke,
    super.key,
  }) : assert(device != null || request != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentDevice = device;
    final currentRequest = request;
    final displayName =
        currentDevice?.displayName ?? currentRequest!.displayName;
    final lastSeen = currentDevice?.lastSeenAt == null
        ? context.tr(
            'authorized_devices.last_seen.never',
            fallback: 'Jamais vu',
          )
        : context.tr(
            'authorized_devices.last_seen.at',
            fallback: 'Dernière activité : {date}',
            values: {'date': _formatDateTime(currentDevice!.lastSeenAt!)},
          );
    final requestPending = currentRequest?.isPending ?? false;
    final requestWorkspaceAlreadyShown =
        currentDevice?.effectiveWorkspaces.any(
          (workspace) => workspace.tenantId == currentRequest?.tenantId,
        ) ??
        false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              currentDevice == null
                  ? Icons.phonelink_lock_outlined
                  : currentDevice.isActive
                  ? Icons.devices_outlined
                  : Icons.block_outlined,
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
                      Text(displayName, style: theme.textTheme.titleMedium),
                      if (currentDevice != null)
                        _StatusBadge(
                          backgroundColor: currentDevice.isActive
                              ? colorScheme.primaryContainer
                              : colorScheme.errorContainer,
                          foregroundColor: currentDevice.isActive
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onErrorContainer,
                          label: context.tr(
                            'authorized_devices.terminal_status',
                            fallback: 'Terminal : {status}',
                            values: {
                              'status': context.trText(
                                currentDevice.statusLabel,
                              ),
                            },
                          ),
                        ),
                      if (currentRequest != null)
                        _StatusBadge(
                          backgroundColor: requestPending
                              ? colorScheme.tertiaryContainer
                              : colorScheme.surfaceContainerHighest,
                          foregroundColor: requestPending
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                          label: context.tr(
                            'authorized_devices.request_status',
                            fallback: 'Demande : {status}',
                            values: {
                              'status': context.trText(
                                currentRequest.statusLabel,
                              ),
                            },
                          ),
                        ),
                      for (final workspace
                          in currentDevice?.effectiveWorkspaces ??
                              const <AuthorizedDeviceWorkspace>[])
                        Chip(
                          avatar: Icon(
                            workspace.isActive
                                ? Icons.account_tree_outlined
                                : Icons.block_outlined,
                            size: 18,
                          ),
                          label: Text(workspace.tenantLabel),
                        ),
                      if (currentRequest != null &&
                          !requestWorkspaceAlreadyShown &&
                          currentRequest.tenantId.trim().isNotEmpty)
                        Chip(
                          avatar: const Icon(
                            Icons.account_tree_outlined,
                            size: 18,
                          ),
                          label: Text(currentRequest.tenantLabel),
                        ),
                      if (isCurrentDevice)
                        _StatusBadge(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          label: context.tr(
                            'authorized_devices.current_device',
                            fallback: 'Ce terminal',
                          ),
                        ),
                    ],
                  ),
                  if (currentDevice != null) ...[
                    const SizedBox(height: 8),
                    Text('${currentDevice.platformLabel} — $lastSeen'),
                    const SizedBox(height: 4),
                    Text(
                      currentDevice.workspaceCount > 1
                          ? context.tr(
                              'authorized_devices.enrolled.multiple',
                              fallback:
                                  'Enrollé dans {count} espaces : {summary}',
                              values: {
                                'count': currentDevice.workspaceCount,
                                'summary': currentDevice.workspaceSummary,
                              },
                            )
                          : context.tr(
                              'authorized_devices.enrolled.single',
                              fallback: 'Enrollé dans {summary}',
                              values: {
                                'summary': currentDevice.workspaceSummary,
                              },
                            ),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        'authorized_devices.device_id',
                        fallback: 'Identifiant terminal : {deviceId}',
                        values: {'deviceId': currentDevice.deviceId},
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        'authorized_devices.created_at',
                        fallback: 'Créé le {date}',
                        values: {
                          'date': _formatDateTime(currentDevice.createdAt),
                        },
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (currentDevice.revokedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'authorized_devices.revoked_at',
                          fallback: 'Révoqué le {date}',
                          values: {
                            'date': _formatDateTime(currentDevice.revokedAt),
                          },
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                  if (currentRequest != null) ...[
                    if (currentDevice != null) ...[
                      const SizedBox(height: 10),
                      const Divider(),
                    ] else
                      const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'authorized_devices.requests.requested_at',
                        fallback: '{platform} — demandée le {date}',
                        values: {
                          'platform': currentRequest.platformLabel,
                          'date': _formatDateTime(currentRequest.requestedAt),
                        },
                      ),
                    ),
                    if (currentRequest.requesterEmail.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'authorized_devices.requests.requester_email',
                          fallback: 'Demandeur : {email}',
                          values: {'email': currentRequest.requesterEmail},
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (currentRequest.requesterNote.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        currentRequest.requesterNote,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (currentRequest.decidedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'authorized_devices.requests.decided_at',
                          fallback: 'Traitée le {date}',
                          values: {
                            'date': _formatDateTime(currentRequest.decidedAt),
                          },
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (requestCount > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'authorized_devices.requests.history_count',
                          fallback:
                              '{count} demandes d’enrôlement associées à ce terminal.',
                          values: {'count': requestCount},
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (currentRequest.isPending &&
                        onApprove != null &&
                        onReject != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: working ? null : onReject,
                              icon: const Icon(Icons.block_outlined),
                              label: Text(
                                context.tr(
                                  'common.reject',
                                  fallback: 'Refuser',
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: working ? null : onApprove,
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(
                                context.tr(
                                  'common.approve',
                                  fallback: 'Approuver',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (currentDevice != null)
              PopupMenuButton<String>(
                enabled: !working,
                onSelected: (value) {
                  if (value == 'rename') {
                    onRename?.call();
                  } else if (value == 'revoke') {
                    onRevoke?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'rename',
                    enabled: currentDevice.isActive && onRename != null,
                    child: Text(
                      context.tr(
                        'authorized_devices.action.rename',
                        fallback: 'Renommer',
                      ),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'revoke',
                    enabled: currentDevice.isActive && onRevoke != null,
                    child: Text(
                      currentDevice.workspaceCount > 1
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

class EnrollmentRequestCard extends StatelessWidget {
  final DeviceEnrollmentRequest request;
  final bool working;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const EnrollmentRequestCard({
    required this.request,
    required this.working,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AuthorizedTerminalCard(
      device: null,
      request: request,
      requestCount: 1,
      working: working,
      isCurrentDevice: false,
      onApprove: onApprove,
      onReject: onReject,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final String label;

  const _StatusBadge({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(label, style: TextStyle(color: foregroundColor)),
      ),
    );
  }
}

class _ReusableEnrollmentInvitationsSection extends StatelessWidget {
  final List<DeviceEnrollmentInvitation> invitations;
  final bool working;
  final bool canRevoke;
  final ValueChanged<DeviceEnrollmentInvitation> onRevoke;

  const _ReusableEnrollmentInvitationsSection({
    required this.invitations,
    required this.working,
    required this.canRevoke,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
            'authorized_devices.invitations.title',
            fallback: 'Invitations permanentes',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final invitation in invitations) ...[
          ReusableEnrollmentInvitationCard(
            invitation: invitation,
            working: working,
            canRevoke: canRevoke,
            onRevoke: () => onRevoke(invitation),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class ReusableEnrollmentInvitationCard extends StatelessWidget {
  final DeviceEnrollmentInvitation invitation;
  final bool working;
  final bool canRevoke;
  final VoidCallback onRevoke;

  const ReusableEnrollmentInvitationCard({
    required this.invitation,
    required this.working,
    required this.canRevoke,
    required this.onRevoke,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invitation.label.trim().isEmpty
              ? context.tr(
                  'authorized_devices.invitations.unnamed',
                  fallback: 'Invitation permanente',
                )
              : invitation.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'authorized_devices.invitations.capacity',
            fallback:
                '{active}/{maximum} terminaux actifs — {uses} utilisation(s)',
            values: {
              'active': invitation.activeDeviceCount,
              'maximum': invitation.maxActiveDevices,
              'uses': invitation.useCount,
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'authorized_devices.invitations.created',
            fallback: 'Créée le {date} — {workspace}',
            values: {
              'date': _formatDateTime(invitation.createdAt),
              'workspace': invitation.tenantDisplayName,
            },
          ),
        ),
        if (invitation.lastUsedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
              'authorized_devices.invitations.last_used',
              fallback: 'Dernière utilisation : {date}',
              values: {'date': _formatDateTime(invitation.lastUsedAt)},
            ),
          ),
        ],
        if (!invitation.isActive && invitation.revokedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
              'authorized_devices.invitations.revoked_at',
              fallback: 'Révoquée le {date}',
              values: {'date': _formatDateTime(invitation.revokedAt)},
            ),
          ),
        ],
      ],
    );
    final action = invitation.isActive && canRevoke
        ? FilledButton.tonalIcon(
            onPressed: working ? null : onRevoke,
            icon: const Icon(Icons.link_off_outlined),
            label: Text(
              context.tr(
                'authorized_devices.invitations.revoke',
                fallback: 'Révoquer l’invitation',
              ),
            ),
          )
        : Chip(
            label: Text(
              invitation.isActive
                  ? context.tr(
                      'authorized_devices.invitations.active',
                      fallback: 'Active',
                    )
                  : context.tr(
                      'authorized_devices.invitations.revoked',
                      fallback: 'Révoquée',
                    ),
            ),
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 680) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                action,
              ],
            );
          },
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

class _RevokeEnrollmentInvitationDialog extends StatefulWidget {
  final DeviceEnrollmentInvitation invitation;

  const _RevokeEnrollmentInvitationDialog({required this.invitation});

  @override
  State<_RevokeEnrollmentInvitationDialog> createState() =>
      _RevokeEnrollmentInvitationDialogState();
}

class _RevokeEnrollmentInvitationDialogState
    extends State<_RevokeEnrollmentInvitationDialog> {
  bool _revokeDevices = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'authorized_devices.invitations.revoke_title',
          fallback: 'Révoquer cette invitation ?',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'authorized_devices.invitations.revoke_message',
                fallback:
                    'Le code ne pourra plus autoriser de nouveaux terminaux.',
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _revokeDevices,
              onChanged: (value) {
                setState(() {
                  _revokeDevices = value ?? true;
                });
              },
              title: Text(
                context.tr(
                  'authorized_devices.invitations.revoke_devices',
                  fallback:
                      'Révoquer également les terminaux et leurs sessions',
                ),
              ),
              subtitle: Text(
                context.tr(
                  'authorized_devices.invitations.revoke_devices_help',
                  fallback:
                      '{count} terminal(aux) actif(s) ont été enrôlés avec cette invitation.',
                  values: {'count': widget.invitation.activeDeviceCount},
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.cancel', fallback: 'Annuler')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_revokeDevices),
          icon: const Icon(Icons.link_off_outlined),
          label: Text(
            context.tr(
              'authorized_devices.action.revoke',
              fallback: 'Révoquer',
            ),
          ),
        ),
      ],
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
  bool _reusable = false;
  int _maxActiveDevices = 10;

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
                _reusable
                    ? context.tr(
                        'authorized_devices.enrollment.reusable_help',
                        fallback:
                            'Cette invitation reste utilisable jusqu’à sa révocation. Chaque terminal reçoit son propre jeton révocable.',
                      )
                    : context.tr(
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
              if (widget.activeUser.role == AppUserRole.administrator) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reusable,
                  onChanged: (value) {
                    setState(() {
                      _reusable = value;
                    });
                  },
                  title: Text(
                    context.tr(
                      'authorized_devices.enrollment.reusable',
                      fallback: 'Invitation permanente révocable',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'authorized_devices.enrollment.reusable_admin_only',
                      fallback:
                          'Réservée aux administrateurs pour un besoin de recette ou de certification.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_reusable)
                DropdownButtonFormField<int>(
                  initialValue: _maxActiveDevices,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'authorized_devices.enrollment.max_active_devices',
                      fallback: 'Nombre maximal de terminaux actifs',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5')),
                    DropdownMenuItem(value: 10, child: Text('10')),
                    DropdownMenuItem(value: 20, child: Text('20')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _maxActiveDevices = value;
                    });
                  },
                )
              else
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
              reusable: _reusable,
              maxActiveDevices: _maxActiveDevices,
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

class _EnrollmentCodeDialog extends StatefulWidget {
  final OpenIrnApiEnrollmentResult enrollment;
  final String requesterEmail;
  final Future<OpenIrnApiEnrollmentResult> Function()? onSendEmail;

  const _EnrollmentCodeDialog({
    required this.enrollment,
    this.requesterEmail = '',
    this.onSendEmail,
  });

  @override
  State<_EnrollmentCodeDialog> createState() => _EnrollmentCodeDialogState();
}

class _EnrollmentCodeDialogState extends State<_EnrollmentCodeDialog> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _sendEmail() async {
    final send = widget.onSendEmail;
    if (send == null || _sending || _sent) {
      return;
    }
    setState(() {
      _sending = true;
    });
    final result = await send();
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _sent = result.isAccepted;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title} — ${result.message}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enrollment = widget.enrollment;
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
            Text(
              enrollment.reusable
                  ? context.tr(
                      'authorized_devices.enrollment.reusable_capacity',
                      fallback:
                          'Valable jusqu’à révocation — maximum {count} terminaux actifs.',
                      values: {'count': enrollment.maxActiveDevices},
                    )
                  : expiresAt,
            ),
            const SizedBox(height: 12),
            Text(
              enrollment.reusable
                  ? context.tr(
                      'authorized_devices.enrollment.reusable_code',
                      fallback:
                          'Ce code peut être réutilisé jusqu’à sa révocation. Il ne sera plus affiché après fermeture de cette fenêtre.',
                    )
                  : context.tr(
                      'authorized_devices.enrollment.one_time_code',
                      fallback:
                          'Ce code est à usage unique. Il ne sera plus affiché après fermeture de cette fenêtre.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.requesterEmail.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.tr(
                  'authorized_devices.enrollment.email_recipient',
                  fallback: 'Destinataire : {email}',
                  values: {'email': widget.requesterEmail},
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
        if (widget.onSendEmail != null)
          FilledButton.tonalIcon(
            onPressed: _sending || _sent ? null : _sendEmail,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _sent
                        ? Icons.mark_email_read_outlined
                        : Icons.send_outlined,
                  ),
            label: Text(
              _sent
                  ? context.tr(
                      'authorized_devices.enrollment.email_sent',
                      fallback: 'Email envoyé',
                    )
                  : context.tr(
                      'authorized_devices.enrollment.send_email',
                      fallback: 'Envoyer par email',
                    ),
            ),
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
  final List<DeviceEnrollmentInvitation> enrollmentInvitations;
  final bool includeAllTenants;
  final bool serverAvailable;
  final String title;
  final String message;

  const _AuthorizedDevicesStateData({
    required this.configuration,
    required this.devices,
    this.enrollmentRequests = const <DeviceEnrollmentRequest>[],
    this.enrollmentInvitations = const <DeviceEnrollmentInvitation>[],
    required this.includeAllTenants,
    required this.serverAvailable,
    required this.title,
    required this.message,
  });
}

class _EnrollmentFormResult {
  final String label;
  final int expiresInMinutes;
  final bool reusable;
  final int maxActiveDevices;

  const _EnrollmentFormResult({
    required this.label,
    required this.expiresInMinutes,
    required this.reusable,
    required this.maxActiveDevices,
  });
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return OpenIrnLocalizations.instance.tr(
      'common.unknown_date',
      fallback: 'date inconnue',
    );
  }
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
