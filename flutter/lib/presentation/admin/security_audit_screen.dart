import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/security_audit_event.dart';
import '../../domain/models/sync_configuration.dart';
import '../common/openirn_app_bar.dart';

class SecurityAuditScreen extends StatefulWidget {
  final AppUser activeUser;

  const SecurityAuditScreen({required this.activeUser, super.key});

  @override
  State<SecurityAuditScreen> createState() => _SecurityAuditScreenState();
}

class _SecurityAuditScreenState extends State<SecurityAuditScreen> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();

  late Future<_SecurityAuditStateData> _future;
  bool _includeAuthAttempts = true;
  bool _includeDeviceAudit = true;
  int _limit = 100;

  @override
  void initState() {
    super.initState();
    _future = _loadEvents();
  }

  Future<_SecurityAuditStateData> _loadEvents() async {
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _SecurityAuditStateData(
        configuration: configuration,
        events: const <SecurityAuditEvent>[],
        serverAvailable: false,
        title: 'API non configurée',
        message:
            'La synchronisation serveur n’est pas configurée sur ce terminal.',
      );
    }

    final result = await _apiClient.loadSecurityAuditEvents(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      limit: _limit,
      includeAuthAttempts: _includeAuthAttempts,
      includeDeviceAudit: _includeDeviceAudit,
    );

    return _SecurityAuditStateData(
      configuration: configuration,
      events: result.events,
      serverAvailable: result.isAvailable,
      title: result.title,
      message: result.message,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadEvents();
    });
    await _future;
  }

  void _reloadWithFilters() {
    setState(() {
      _future = _loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Journal sécurité',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Actualiser',
            icon: Icons.refresh,
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_SecurityAuditStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final state = snapshot.data;
          if (state == null) {
            return const Center(
              child: Text('Impossible de charger le journal sécurité.'),
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
                      includeAuthAttempts: _includeAuthAttempts,
                      includeDeviceAudit: _includeDeviceAudit,
                      limit: _limit,
                      onIncludeAuthAttemptsChanged: (value) {
                        _includeAuthAttempts = value;
                        _reloadWithFilters();
                      },
                      onIncludeDeviceAuditChanged: (value) {
                        _includeDeviceAudit = value;
                        _reloadWithFilters();
                      },
                      onLimitChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        _limit = value;
                        _reloadWithFilters();
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!state.serverAvailable)
                      _MessageCard(
                        icon: Icons.warning_amber_outlined,
                        title: state.title,
                        message: state.message,
                      )
                    else if (state.events.isEmpty)
                      const _MessageCard(
                        icon: Icons.security_outlined,
                        title: 'Aucun événement sécurité',
                        message:
                            'Aucun événement ne correspond aux filtres sélectionnés.',
                      )
                    else
                      for (final event in state.events) ...[
                        _AuditEventCard(event: event),
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
  final _SecurityAuditStateData state;
  final bool includeAuthAttempts;
  final bool includeDeviceAudit;
  final int limit;
  final ValueChanged<bool> onIncludeAuthAttemptsChanged;
  final ValueChanged<bool> onIncludeDeviceAuditChanged;
  final ValueChanged<int?> onLimitChanged;

  const _HeaderCard({
    required this.state,
    required this.includeAuthAttempts,
    required this.includeDeviceAudit,
    required this.limit,
    required this.onIncludeAuthAttemptsChanged,
    required this.onIncludeDeviceAuditChanged,
    required this.onLimitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 760;
    final authCount = state.events.where((event) => event.isAuthAttempt).length;
    final deviceCount = state.events
        .where((event) => event.isDeviceAudit)
        .length;
    final failureCount = state.events.where((event) => event.isFailure).length;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.security_outlined, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Journal sécurité serveur',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                state.serverAvailable
                    ? '${state.events.length} événement(s) — $authCount authentification(s), $deviceCount terminal(aux), $failureCount échec(s) — tenant ${state.configuration.tenantId}'
                    : state.message,
              ),
            ],
          ),
        ),
      ],
    );

    final filters = Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Authentifications'),
          value: includeAuthAttempts,
          onChanged: onIncludeAuthAttemptsChanged,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Terminaux / sessions'),
          value: includeDeviceAudit,
          onChanged: onIncludeDeviceAuditChanged,
        ),
        DropdownButtonFormField<int>(
          initialValue: limit,
          decoration: const InputDecoration(
            labelText: 'Nombre maximum',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 50, child: Text('50 événements')),
            DropdownMenuItem(value: 100, child: Text('100 événements')),
            DropdownMenuItem(value: 200, child: Text('200 événements')),
            DropdownMenuItem(value: 500, child: Text('500 événements')),
          ],
          onChanged: onLimitChanged,
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 12), filters],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 18),
                  SizedBox(width: 320, child: filters),
                ],
              ),
      ),
    );
  }
}

class _AuditEventCard extends StatelessWidget {
  final SecurityAuditEvent event;

  const _AuditEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final colors = _badgeColors(context, event);
    final icon = event.isAuthAttempt
        ? event.isSuccess
              ? Icons.login_outlined
              : Icons.lock_person_outlined
        : Icons.devices_other_outlined;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 34),
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
                        event.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _Badge(label: event.sourceLabel, colors: colors),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(event.subtitle),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(event.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (event.payload.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _compactPayload(event.payload),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeColors _badgeColors(BuildContext context, SecurityAuditEvent event) {
    if (event.isFailure) {
      return _BadgeColors(
        background: Theme.of(context).colorScheme.errorContainer,
        foreground: Theme.of(context).colorScheme.onErrorContainer,
      );
    }
    if (event.isAuthAttempt) {
      return _BadgeColors(
        background: Theme.of(context).colorScheme.primaryContainer,
        foreground: Theme.of(context).colorScheme.onPrimaryContainer,
      );
    }
    return _BadgeColors(
      background: Theme.of(context).colorScheme.secondaryContainer,
      foreground: Theme.of(context).colorScheme.onSecondaryContainer,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final _BadgeColors colors;

  const _Badge({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(label, style: TextStyle(color: colors.foreground)),
      ),
    );
  }
}

class _BadgeColors {
  final Color background;
  final Color foreground;

  const _BadgeColors({required this.background, required this.foreground});
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

class _SecurityAuditStateData {
  final SyncConfiguration configuration;
  final List<SecurityAuditEvent> events;
  final bool serverAvailable;
  final String title;
  final String message;

  const _SecurityAuditStateData({
    required this.configuration,
    required this.events,
    required this.serverAvailable,
    required this.title,
    required this.message,
  });
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String _compactPayload(Map<String, dynamic> payload) {
  final visible = payload.entries
      .where(
        (entry) =>
            entry.value != null && entry.value.toString().trim().isNotEmpty,
      )
      .take(4)
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(' — ');
  return visible.isEmpty
      ? 'Détails techniques disponibles côté serveur.'
      : visible;
}
