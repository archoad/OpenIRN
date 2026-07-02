import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/authorized_device.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/app_sync_coordinator.dart';
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
    if (!_accessPolicy.canManageAuthorizedDevices(widget.activeUser)) {
      return _AuthorizedDevicesStateData(
        configuration: SyncConfiguration.empty(),
        devices: const <AuthorizedDevice>[],
        serverAvailable: false,
        title: 'Accès refusé',
        message:
            'La gestion des terminaux autorisés est réservée aux administrateurs.',
      );
    }
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _AuthorizedDevicesStateData(
        configuration: configuration,
        devices: const <AuthorizedDevice>[],
        serverAvailable: false,
        title: 'Serveur non configuré',
        message:
            'La synchronisation serveur n’est pas configurée sur ce terminal. Impossible de gérer les terminaux autorisés.',
      );
    }

    final result = await _apiClient.loadDevices(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    return _AuthorizedDevicesStateData(
      configuration: configuration,
      devices: result.devices,
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
        tenantId: state.configuration.tenantId,
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
        title: const Text('Révoquer ce terminal ?'),
        content: ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            'Le terminal « ${device.displayName} » ne pourra plus utiliser son jeton OpenIRN. '
            'Cette opération est recommandée si le terminal est perdu, remplacé ou compromis.'
            '${isCurrentDevice ? '\n\nAttention : il s’agit du terminal courant. Son autorisation locale sera aussi supprimée après révocation.' : ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.block_outlined),
            label: const Text('Révoquer'),
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
        tenantId: state.configuration.tenantId,
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
        const SnackBar(
          content: Text(
            'Terminal courant révoqué. Veuillez autoriser de nouveau ce terminal pour resynchroniser.',
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
            return const Center(
              child: Text('Impossible de charger les terminaux autorisés.'),
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
                    if (!state.serverAvailable)
                      _MessageCard(
                        icon: Icons.warning_amber_outlined,
                        title: state.title,
                        message: state.message,
                      )
                    else if (state.devices.isEmpty)
                      const _MessageCard(
                        icon: Icons.devices_other_outlined,
                        title: 'Aucun terminal enregistré',
                        message:
                            'Créez une invitation pour autoriser le premier terminal avec un code individuel.',
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
                'Terminaux autorisés',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                state.serverAvailable
                    ? '$activeCount actif(s), $revokedCount révoqué(s) — espace ${state.configuration.tenantId}'
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
                    label: const Text('Autoriser un nouveau terminal'),
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
                    label: const Text('Autoriser un nouveau terminal'),
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
        ? 'Jamais vu'
        : 'Dernière activité : ${_formatDateTime(device.lastSeenAt!)}';
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
                            device.statusLabel,
                            style: TextStyle(color: statusTextColor),
                          ),
                        ),
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
                              'Ce terminal',
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
                    'Créé le ${_formatDateTime(device.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (device.revokedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Révoqué le ${_formatDateTime(device.revokedAt)}',
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
                  child: const Text('Renommer'),
                ),
                PopupMenuItem<String>(
                  value: 'revoke',
                  enabled: device.isActive,
                  child: const Text('Révoquer'),
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
      text: 'Invitation créée par $userName',
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
      title: const Text('Autoriser un nouveau terminal'),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OpenIRN va générer un code court à usage unique. Le nouveau terminal devra saisir ce code avant expiration.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelController,
                autofocus: shouldAutofocusTextField(context),
                decoration: const InputDecoration(
                  labelText: 'Libellé interne',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _expiresInMinutes,
                decoration: const InputDecoration(
                  labelText: 'Durée de validité',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 minutes')),
                  DropdownMenuItem(value: 10, child: Text('10 minutes')),
                  DropdownMenuItem(value: 15, child: Text('15 minutes')),
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
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            _EnrollmentFormResult(
              label: _labelController.text.trim(),
              expiresInMinutes: _expiresInMinutes,
            ),
          ),
          icon: const Icon(Icons.add_link_outlined),
          label: const Text('Créer le code'),
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
        ? 'Expiration non précisée'
        : 'Expire le ${_formatDateTime(enrollment.expiresAt)}';

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Code d’appairage'),
      content: ResponsiveDialogContent(
        maxWidth: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sur le nouveau terminal, ouvrez OpenIRN puis choisissez « Autoriser ce terminal ». Saisissez ensuite le code ci-dessous.',
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
              'Ce code est à usage unique. Il ne sera plus affiché après fermeture de cette fenêtre.',
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Code copié.')));
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copier'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
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
      title: const Text('Renommer le terminal'),
      content: ResponsiveDialogContent(
        maxWidth: 620,
        child: TextField(
          controller: _controller,
          autofocus: shouldAutofocusTextField(context),
          decoration: const InputDecoration(
            labelText: 'Nom du terminal',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(context),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => _submit(context),
          child: const Text('Renommer'),
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
  final bool serverAvailable;
  final String title;
  final String message;

  const _AuthorizedDevicesStateData({
    required this.configuration,
    required this.devices,
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
