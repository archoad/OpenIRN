import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/api_session.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/sync_configuration.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_dialog.dart';

class ServerSessionsScreen extends StatefulWidget {
  final AppUser activeUser;

  const ServerSessionsScreen({required this.activeUser, super.key});

  @override
  State<ServerSessionsScreen> createState() => _ServerSessionsScreenState();
}

class _ServerSessionsScreenState extends State<ServerSessionsScreen> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();

  late Future<_ServerSessionsStateData> _future;
  bool _working = false;
  bool _includeInactive = true;

  @override
  void initState() {
    super.initState();
    _future = _loadSessions();
  }

  Future<_ServerSessionsStateData> _loadSessions() async {
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _ServerSessionsStateData(
        configuration: configuration,
        sessions: const <ApiSessionInfo>[],
        serverAvailable: false,
        title: 'API non configurée',
        message:
            'La synchronisation serveur n’est pas configurée sur ce terminal.',
      );
    }

    final result = await _apiClient.loadApiSessions(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      includeInactive: _includeInactive,
    );

    return _ServerSessionsStateData(
      configuration: configuration,
      sessions: result.sessions,
      serverAvailable: result.isAvailable,
      title: result.title,
      message: result.message,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSessions();
    });
    await _future;
  }

  Future<void> _revokeSession(
    _ServerSessionsStateData state,
    ApiSessionInfo session,
  ) async {
    if (_working || !state.configuration.isConfigured || !session.isActive) {
      return;
    }
    if (session.isCurrentSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La session courante ne peut pas être révoquée depuis cette page. Ferme l’application pour la terminer.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Révoquer cette session ?'),
        content: ResponsiveDialogContent(
          maxWidth: 640,
          child: Text(
            'La session de ${session.displayUser} sur « ${session.displayDevice} » sera invalidée immédiatement. '
            'Le terminal devra redemander un code personnel pour ouvrir une nouvelle session.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Révoquer'),
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
      final result = await _apiClient.revokeApiSession(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        sessionId: session.sessionId,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Sessions serveur',
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
      body: FutureBuilder<_ServerSessionsStateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final state = snapshot.data;
          if (state == null) {
            return const Center(
              child: Text('Impossible de charger les sessions serveur.'),
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
                      includeInactive: _includeInactive,
                      onIncludeInactiveChanged: _working
                          ? null
                          : (value) {
                              setState(() {
                                _includeInactive = value;
                                _future = _loadSessions();
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    if (!state.serverAvailable)
                      _MessageCard(
                        icon: Icons.warning_amber_outlined,
                        title: state.title,
                        message: state.message,
                      )
                    else if (state.sessions.isEmpty)
                      const _MessageCard(
                        icon: Icons.lock_clock_outlined,
                        title: 'Aucune session serveur',
                        message:
                            'Aucune session courte n’est actuellement connue côté serveur.',
                      )
                    else
                      for (final session in state.sessions) ...[
                        _SessionCard(
                          session: session,
                          working: _working,
                          onRevoke: () => _revokeSession(state, session),
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
  final _ServerSessionsStateData state;
  final bool includeInactive;
  final ValueChanged<bool>? onIncludeInactiveChanged;

  const _HeaderCard({
    required this.state,
    required this.includeInactive,
    required this.onIncludeInactiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = state.sessions
        .where((session) => session.isActive)
        .length;
    final expiredCount = state.sessions
        .where((session) => session.isExpired)
        .length;
    final revokedCount = state.sessions
        .where((session) => session.isRevoked)
        .length;
    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_clock_outlined, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sessions serveur',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                state.serverAvailable
                    ? '$activeCount active(s), $expiredCount expirée(s), $revokedCount révoquée(s) — tenant ${state.configuration.tenantId}'
                    : state.message,
              ),
            ],
          ),
        ),
      ],
    );

    final toggle = SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Afficher les sessions inactives'),
      subtitle: const Text('Inclut les sessions expirées ou révoquées.'),
      value: includeInactive,
      onChanged: onIncludeInactiveChanged,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 8), toggle],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  SizedBox(width: 340, child: toggle),
                ],
              ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ApiSessionInfo session;
  final bool working;
  final VoidCallback onRevoke;

  const _SessionCard({
    required this.session,
    required this.working,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final statusColors = _statusColors(context, session);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              session.isActive
                  ? Icons.verified_user_outlined
                  : Icons.lock_reset_outlined,
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
                        session.displayUser,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _Badge(label: session.statusLabel, colors: statusColors),
                      if (session.isCurrentSession)
                        _Badge(
                          label: 'Session courante',
                          colors: _BadgeColors(
                            background: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            foreground: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${session.displayDevice}${session.devicePlatform.isEmpty ? '' : ' — ${session.devicePlatform}'}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Créée le ${_formatDateTime(session.createdAt)} — expire le ${_formatDateTime(session.expiresAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dernière activité : ${_formatDateTime(session.lastSeenAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (session.revokedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Révoquée le ${_formatDateTime(session.revokedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: !working,
              onSelected: (value) {
                if (value == 'revoke') {
                  onRevoke();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'revoke',
                  enabled: session.isActive && !session.isCurrentSession,
                  child: const Text('Révoquer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _BadgeColors _statusColors(BuildContext context, ApiSessionInfo session) {
    if (session.isActive) {
      return _BadgeColors(
        background: Theme.of(context).colorScheme.primaryContainer,
        foreground: Theme.of(context).colorScheme.onPrimaryContainer,
      );
    }
    if (session.isRevoked) {
      return _BadgeColors(
        background: Theme.of(context).colorScheme.errorContainer,
        foreground: Theme.of(context).colorScheme.onErrorContainer,
      );
    }
    return _BadgeColors(
      background: Theme.of(context).colorScheme.surfaceContainerHighest,
      foreground: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _ServerSessionsStateData {
  final SyncConfiguration configuration;
  final List<ApiSessionInfo> sessions;
  final bool serverAvailable;
  final String title;
  final String message;

  const _ServerSessionsStateData({
    required this.configuration,
    required this.sessions,
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
