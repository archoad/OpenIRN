import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/security_audit_event.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
import '../../l10n/openirn_localizations.dart';
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
  final _accessPolicy = const AccessPolicyService();

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
    if (!_accessPolicy.canViewSecurityAudit(widget.activeUser)) {
      return _SecurityAuditStateData(
        configuration: SyncConfiguration.empty(),
        events: const <SecurityAuditEvent>[],
        serverAvailable: false,
        title: OpenIrnLocalizations.instance.tr(
          'screen.security.access_denied',
        ),
        message: OpenIrnLocalizations.instance.tr(
          'security.error.access_denied.message',
        ),
      );
    }
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _SecurityAuditStateData(
        configuration: configuration,
        events: const <SecurityAuditEvent>[],
        serverAvailable: false,
        title: OpenIrnLocalizations.instance.tr(
          'screen.security.server_not_configured',
        ),
        message: OpenIrnLocalizations.instance.tr(
          'security.error.server_not_configured.message',
        ),
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
            return Center(
              child: Text(context.tr('security.error.load_failed')),
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
                      _MessageCard(
                        icon: Icons.security_outlined,
                        title: context.tr('screen.security.empty'),
                        message: context.tr('security.empty.message'),
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
                context.tr('security.header.title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                state.serverAvailable
                    ? context.tr(
                        'security.header.summary',
                        values: {
                          'events': state.events.length,
                          'auth': authCount,
                          'devices': deviceCount,
                          'failures': failureCount,
                          'workspace': state.configuration.tenantLabel,
                        },
                      )
                    : context.trText(state.message),
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
          title: Text(context.tr('security.filter.authentications')),
          value: includeAuthAttempts,
          onChanged: onIncludeAuthAttemptsChanged,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('security.filter.devices_sessions')),
          value: includeDeviceAudit,
          onChanged: onIncludeDeviceAuditChanged,
        ),
        DropdownButtonFormField<int>(
          initialValue: limit,
          decoration: InputDecoration(
            labelText: context.tr('security.filter.limit'),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 50,
              child: Text(
                context.tr(
                  'security.filter.event_limit',
                  values: {'count': 50},
                ),
              ),
            ),
            DropdownMenuItem(
              value: 100,
              child: Text(
                context.tr(
                  'security.filter.event_limit',
                  values: {'count': 100},
                ),
              ),
            ),
            DropdownMenuItem(
              value: 200,
              child: Text(
                context.tr(
                  'security.filter.event_limit',
                  values: {'count': 200},
                ),
              ),
            ),
            DropdownMenuItem(
              value: 500,
              child: Text(
                context.tr(
                  'security.filter.event_limit',
                  values: {'count': 500},
                ),
              ),
            ),
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
                        context.trText(event.title),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _Badge(
                        label: context.trText(event.sourceLabel),
                        colors: colors,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_localizedAuditSubtitle(context, event)),
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
                  Text(
                    context.trText(title),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(context.trText(message)),
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
      ? OpenIrnLocalizations.instance.tr('security.event.technical_details')
      : visible;
}

String _localizedAuditSubtitle(BuildContext context, SecurityAuditEvent event) {
  final parts = <String>[];
  if (event.deviceId.trim().isNotEmpty) {
    parts.add(
      context.tr('security.event.device', values: {'device': event.deviceId}),
    );
  }
  if (event.userId.trim().isNotEmpty) {
    parts.add(
      context.tr('security.event.user', values: {'user': event.userId}),
    );
  }
  if (event.ipAddress.trim().isNotEmpty) {
    parts.add('IP ${event.ipAddress}');
  }
  if (event.reason.trim().isNotEmpty) {
    parts.add(event.reason);
  }
  return parts.isEmpty
      ? context.tr('security.event.no_details')
      : parts.join(' — ');
}
