import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/repositories/irn_referential_repository.dart';
import '../../domain/services/app_session_manager.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../about/about_screen.dart';
import '../admin/administration_screen.dart';
import '../campaigns/campaign_list_screen.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';
import '../sync/device_enrollment_screen.dart';
import 'criterion_detail_screen.dart';

class ReferentialOverviewScreen extends StatefulWidget {
  final IrnReferentialRepository repository;

  const ReferentialOverviewScreen({required this.repository, super.key});

  @override
  State<ReferentialOverviewScreen> createState() =>
      _ReferentialOverviewScreenState();
}

class _ReferentialOverviewScreenState extends State<ReferentialOverviewScreen> {
  final _syncConfigurationRepository = const LocalSyncConfigurationRepository();
  late Future<_ReferentialBootstrap> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  Future<_ReferentialBootstrap> _loadBootstrap() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();

    if (!configuration.isConfigured) {
      AppSyncCoordinator.instance.stop();
      return _ReferentialBootstrap(
        referential: _emptyServerReferential(),
        configuration: configuration,
        referentialError: null,
        requiresDeviceEnrollment: true,
      );
    }

    try {
      final referential = await widget.repository.getActiveReferential();
      AppSyncCoordinator.instance.start(referential: referential);
      return _ReferentialBootstrap(
        referential: referential,
        configuration: configuration,
        referentialError: null,
        requiresDeviceEnrollment: false,
      );
    } catch (error) {
      AppSyncCoordinator.instance.stop();
      final errorMessage = error.toString();
      return _ReferentialBootstrap(
        referential: _emptyServerReferential(),
        configuration: configuration,
        referentialError: errorMessage,
        requiresDeviceEnrollment: _isDeviceEnrollmentRequiredError(
          errorMessage,
        ),
      );
    }
  }

  void _reloadBootstrap() {
    setState(() {
      _bootstrapFuture = _loadBootstrap();
    });
  }

  Future<void> _openAbout() async {
    final bootstrap = await _bootstrapFuture;
    if (!mounted) {
      return;
    }
    if (!bootstrap.hasReferential) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le référentiel serveur doit être chargé avant d’ouvrir À propos.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AboutScreen(referential: bootstrap.referential),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'OpenIRN',
        actions: [
          OpenIrnAppBarAction(
            id: 'about',
            label: 'À propos / Licence',
            icon: Icons.info_outline,
            onPressed: _openAbout,
          ),
        ],
      ),
      body: FutureBuilder<_ReferentialBootstrap>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error.toString());
          }
          final bootstrap = snapshot.data;
          if (bootstrap == null) {
            return const _ErrorState(error: 'État d’accueil absent.');
          }

          return _HomeContent(
            referential: bootstrap.referential,
            initialConfiguration: bootstrap.configuration,
            referentialError: bootstrap.referentialError,
            requiresDeviceEnrollment: bootstrap.requiresDeviceEnrollment,
            onConfigurationChanged: _reloadBootstrap,
          );
        },
      ),
    );
  }
}

class _ReferentialBootstrap {
  final IrnReferential referential;
  final SyncConfiguration configuration;
  final String? referentialError;
  final bool requiresDeviceEnrollment;

  const _ReferentialBootstrap({
    required this.referential,
    required this.configuration,
    required this.referentialError,
    required this.requiresDeviceEnrollment,
  });

  bool get hasReferential =>
      referential.pillars.isNotEmpty || referential.criteria.isNotEmpty;
}

bool _isDeviceEnrollmentRequiredError(String? message) {
  final normalized = (message ?? '')
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('ù', 'u')
      .replaceAll('ç', 'c');

  if (normalized.contains('terminal non autorise') ||
      normalized.contains('terminal revoque') ||
      normalized.contains('terminal suspendu') ||
      normalized.contains('appairage') ||
      normalized.contains('enrollment')) {
    return true;
  }

  final hasAuthStatus =
      normalized.contains('http 401') ||
      normalized.contains('http 403') ||
      normalized.contains('statut 401') ||
      normalized.contains('statut 403');

  return hasAuthStatus &&
      (normalized.contains('terminal') || normalized.contains('autorisation'));
}

IrnReferential _emptyServerReferential() {
  return IrnReferential(
    id: 'openirn-server-referential-pending',
    version: 'Non chargé',
    importedAt: null,
    source: const IrnSource(
      type: 'server',
      url: SyncConfiguration.fixedApiBaseUrl,
      projectPath: 'digitalresilienceinitiative/adri-irn',
      defaultBranch: 'main',
      filePath: '',
      license: 'Référentiel officiel aDRI IRN',
    ),
    pillars: const <IrnPillar>[],
    criteria: const <IrnCriterion>[],
    importWarnings: const <String>[],
  );
}

class _HomeContent extends StatefulWidget {
  final IrnReferential referential;
  final SyncConfiguration initialConfiguration;
  final String? referentialError;
  final bool requiresDeviceEnrollment;
  final VoidCallback onConfigurationChanged;

  const _HomeContent({
    required this.referential,
    required this.initialConfiguration,
    required this.referentialError,
    required this.requiresDeviceEnrollment,
    required this.onConfigurationChanged,
  });

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  final _syncConfigurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _accessPolicy = const AccessPolicyService();
  late Future<SyncConfiguration> _syncConfigurationFuture;

  String _lastDisplayedLockReason = '';

  @override
  void initState() {
    super.initState();
    _syncConfigurationFuture = Future<SyncConfiguration>.value(
      widget.initialConfiguration,
    );
    AppSessionManager.instance.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    AppSessionManager.instance.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    final reason = AppSessionManager.instance.lastLockReason;
    if (reason.trim().isEmpty || reason == _lastDisplayedLockReason) {
      return;
    }
    _lastDisplayedLockReason = reason;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
    });
  }

  @override
  void didUpdateWidget(covariant _HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialConfiguration.deviceId !=
            widget.initialConfiguration.deviceId ||
        oldWidget.initialConfiguration.enabled !=
            widget.initialConfiguration.enabled ||
        oldWidget.initialConfiguration.tenantId !=
            widget.initialConfiguration.tenantId ||
        oldWidget.requiresDeviceEnrollment != widget.requiresDeviceEnrollment) {
      _syncConfigurationFuture = Future<SyncConfiguration>.value(
        widget.initialConfiguration,
      );
    }
  }

  Future<void> _openDeviceEnrollment() async {
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const DeviceEnrollmentScreen()),
    );
    if (!mounted) {
      return;
    }
    if (enrolled == true) {
      widget.onConfigurationChanged();
      setState(() {
        _syncConfigurationFuture = _syncConfigurationRepository
            .loadConfiguration();
      });
    }
  }

  void _showForbidden(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCampaigns() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!mounted) {
      return;
    }
    if (widget.requiresDeviceEnrollment || !configuration.isConfigured) {
      _showForbidden(
        'Autorise ce terminal avant d’ouvrir une campagne d’évaluation.',
      );
      return;
    }
    final activeUser = AppSessionManager.instance.activeUser;
    if (!AppSessionManager.instance.hasActiveSession || activeUser == null) {
      _showForbidden(
        'Déverrouille OpenIRN avec ton profil et ton code personnel avant d’ouvrir une campagne.',
      );
      return;
    }
    if (!_accessPolicy.can(activeUser, OpenIrnPermission.viewCampaignList)) {
      _showForbidden('Ton profil ne permet pas d’ouvrir les campagnes.');
      return;
    }
    if (!_hasServerReferential) {
      _showForbidden(
        'Installe ou recharge le référentiel officiel aDRI depuis l’administration avant d’ouvrir une campagne.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CampaignListScreen(
          referential: widget.referential,
          activeUser: activeUser,
        ),
      ),
    );
  }

  Future<void> _openReferentialCatalog() async {
    final activeUser = AppSessionManager.instance.activeUser;
    if (!AppSessionManager.instance.hasActiveSession || activeUser == null) {
      _showForbidden(
        'Déverrouille OpenIRN avec ton profil et ton code personnel avant d’ouvrir le référentiel.',
      );
      return;
    }
    if (!_accessPolicy.can(
      activeUser,
      OpenIrnPermission.viewReferentialCatalog,
    )) {
      _showForbidden('Ton profil ne permet pas de consulter le référentiel.');
      return;
    }
    if (!_hasServerReferential) {
      _showForbidden(
        'Le référentiel officiel n’est pas encore chargé depuis le serveur.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReferentialCatalogScreen(referential: widget.referential),
      ),
    );
  }

  bool get _hasServerReferential =>
      widget.referential.pillars.isNotEmpty ||
      widget.referential.criteria.isNotEmpty;

  Future<void> _openAdministration() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!mounted) {
      return;
    }
    if (widget.requiresDeviceEnrollment || !configuration.isConfigured) {
      _showForbidden(
        'Autorise ce terminal avant d’ouvrir la console d’administration.',
      );
      return;
    }

    final activeUser = AppSessionManager.instance.activeUser;
    if (!AppSessionManager.instance.hasActiveSession || activeUser == null) {
      _showForbidden(
        'Déverrouille OpenIRN avec ton profil et ton code personnel avant d’ouvrir l’administration.',
      );
      return;
    }
    if (!_accessPolicy.canOpenAdministration(activeUser)) {
      _showForbidden(_accessPolicy.administrationForbiddenMessage(activeUser));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdministrationScreen(
          referential: widget.referential,
          activeUser: activeUser,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    widget.onConfigurationChanged();
    setState(() {
      _syncConfigurationFuture = _syncConfigurationRepository
          .loadConfiguration();
    });
  }

  Future<void> _unlockSession() async {
    final authenticationData = await _loadAuthenticatableUsers();
    if (!mounted) {
      return;
    }

    if (authenticationData.source !=
        _AdministrationAuthenticationSource.server) {
      _showForbidden(authenticationData.message);
      return;
    }

    final activeUsers = authenticationData.users
        .where((user) => user.active)
        .toList(growable: false);

    if (activeUsers.isEmpty) {
      _showForbidden('Aucun profil utilisateur actif n’est disponible.');
      return;
    }

    final selectedUser = await showDialog<AppUser>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdministrationAuthenticationDialog(
        title: 'Déverrouiller OpenIRN',
        intro:
            'Sélectionne ton profil puis saisis ton code personnel pour ouvrir une session serveur courte.',
        users: activeUsers,
        source: authenticationData.source,
        message: authenticationData.message,
        trailingIcon: Icons.login_outlined,
      ),
    );

    if (selectedUser == null || !mounted) {
      return;
    }

    final verified = await _verifySelectedUser(
      authenticationData: authenticationData,
      user: selectedUser,
    );
    if (!verified || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Session ouverte : ${selectedUser.displayName}')),
    );
    widget.onConfigurationChanged();
    setState(() {
      _syncConfigurationFuture = _syncConfigurationRepository
          .loadConfiguration();
    });
  }

  Future<void> _lockSession() async {
    final sessionToken = AppSessionManager.instance.apiToken;
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();

    if (sessionToken.isNotEmpty && configuration.isConfigured) {
      await _apiClient.revokeCurrentApiSession(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: sessionToken,
      );
    }

    AppSessionManager.instance.clearSession(
      reason: 'Session verrouillée manuellement.',
    );
    AppSyncCoordinator.instance.stop();
    if (!mounted) {
      return;
    }
    widget.onConfigurationChanged();
    setState(() {
      _syncConfigurationFuture = _syncConfigurationRepository
          .loadConfiguration();
    });
  }

  Future<bool> _verifySelectedUser({
    required _AdministrationAuthenticationData authenticationData,
    required AppUser user,
  }) async {
    if (authenticationData.source !=
        _AdministrationAuthenticationSource.server) {
      _showForbidden(
        'Authentification serveur obligatoire pour accéder à l’administration.',
      );
      return false;
    }

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdministrationPinAuthenticationDialog(user: user),
    );
    if (pin == null) {
      return false;
    }

    final result = await _apiClient.verifyUserPin(
      baseUrl: authenticationData.apiBaseUrl,
      tenantId: authenticationData.tenantId,
      apiToken: authenticationData.apiToken,
      userId: user.id,
      pin: pin,
    );

    if (!mounted) {
      return result.isAccepted;
    }

    if (!result.isAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.title} — ${result.message}')),
      );
      return false;
    }

    if (result.mustChangePin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Code initial accepté. Pense à définir un code personnel côté administration API.',
          ),
        ),
      );
    }

    return true;
  }

  Future<_AdministrationAuthenticationData> _loadAuthenticatableUsers() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();

    if (widget.requiresDeviceEnrollment || !configuration.isConfigured) {
      return const _AdministrationAuthenticationData(
        source: _AdministrationAuthenticationSource.localOnly,
        message:
            'Terminal non autorisé : appaire ce terminal avant d’accéder aux fonctions protégées.',
        users: <AppUser>[],
      );
    }

    if (configuration.isConfigured) {
      final centralUsers = await _apiClient.loadUsers(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );

      if (centralUsers.hasUsers) {
        return _AdministrationAuthenticationData(
          source: _AdministrationAuthenticationSource.server,
          message:
              '${centralUsers.message} Sélectionne ton identité puis saisis ton code personnel.',
          users: centralUsers.users,
          apiBaseUrl: configuration.apiBaseUrl,
          tenantId: configuration.tenantId,
          apiToken: configuration.apiToken,
        );
      }

      return _AdministrationAuthenticationData(
        source: _AdministrationAuthenticationSource.localFallback,
        message:
            '${centralUsers.title} — authentification serveur indisponible. Réessaie lorsque le serveur OpenIRN répond.',
        users: const <AppUser>[],
      );
    }

    return const _AdministrationAuthenticationData(
      source: _AdministrationAuthenticationSource.localOnly,
      message:
          'Terminal non autorisé : appaire ce terminal avant d’accéder aux fonctions protégées.',
      users: <AppUser>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncConfiguration>(
      future: _syncConfigurationFuture,
      builder: (context, snapshot) {
        final configuration = snapshot.data;
        final isConfigured = configuration?.isConfigured ?? false;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.requiresDeviceEnrollment || !isConfigured)
                  _HomeActionCard(
                    icon: Icons.phonelink_lock_outlined,
                    title: 'Autoriser ce terminal',
                    subtitle:
                        'Appairer ce poste avec le serveur OpenIRN avant d’accéder aux campagnes et à l’administration.',
                    buttonLabel: 'Appairer',
                    onPressed: _openDeviceEnrollment,
                  )
                else if (!AppSessionManager.instance.hasActiveSession ||
                    AppSessionManager.instance.activeUser == null)
                  _HomeActionCard(
                    icon: Icons.lock_open_outlined,
                    title: 'Déverrouiller OpenIRN',
                    subtitle:
                        'Ouvrir une session serveur courte avec ton profil et ton code personnel.',
                    buttonLabel: 'Déverrouiller',
                    onPressed: _unlockSession,
                  )
                else ...[
                  _SessionStatusCard(
                    user: AppSessionManager.instance.activeUser!,
                    expiresAt: AppSessionManager.instance.expiresAt,
                    idleExpiresAt: AppSessionManager.instance.idleExpiresAt,
                    onLock: _lockSession,
                  ),
                  const SizedBox(height: 12),
                  if (!_hasServerReferential) ...[
                    _ServerReferentialWarningCard(
                      message: widget.referentialError,
                      onOpenAdministration: _openAdministration,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_hasServerReferential) ...[
                    _HomeActionCard(
                      icon: Icons.fact_check_outlined,
                      title: 'Evaluation Indice de Résilience Numérique',
                      subtitle: "Créer ou ouvrir une campagne d'évaluation",
                      buttonLabel: 'Ouvrir',
                      onPressed: _openCampaigns,
                    ),
                    const SizedBox(height: 12),
                    _HomeActionCard(
                      icon: Icons.manage_search_outlined,
                      title: 'Référentiel aDRI IRN',
                      subtitle:
                          'Présentation et moteur de recherche du référentiel IRN',
                      buttonLabel: 'Accéder',
                      onPressed: _openReferentialCatalog,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_accessPolicy.canOpenAdministration(
                    AppSessionManager.instance.activeUser!,
                  ))
                    _HomeActionCard(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Administration',
                      subtitle:
                          'Accéder aux opérations autorisées par ton profil.',
                      buttonLabel: 'Administrer',
                      onPressed: _openAdministration,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SessionStatusCard extends StatelessWidget {
  final AppUser user;
  final DateTime? expiresAt;
  final DateTime? idleExpiresAt;
  final Future<void> Function() onLock;

  const _SessionStatusCard({
    required this.user,
    required this.expiresAt,
    required this.idleExpiresAt,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = user.displayName.trim().isEmpty
        ? user.id
        : user.displayName.trim();
    final expirationText = expiresAt == null
        ? 'Expiration serveur non communiquée'
        : 'Expire à ${_formatSessionExpiration(expiresAt!.toLocal())}';
    final idleText = idleExpiresAt == null
        ? 'Verrouillage automatique après inactivité'
        : 'Verrouillage auto à ${_formatSessionExpiration(idleExpiresAt!.toLocal())} en l’absence d’activité';
    final isNarrow = MediaQuery.sizeOf(context).width < 680;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 38,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session ouverte', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('$displayName — ${user.role.label}'),
              const SizedBox(height: 4),
              Text(
                expirationText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                idleText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
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
                  OutlinedButton.icon(
                    onPressed: () {
                      onLock();
                    },
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Verrouiller'),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      onLock();
                    },
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Verrouiller'),
                  ),
                ],
              ),
      ),
    );
  }
}

String _formatSessionExpiration(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class _ServerReferentialWarningCard extends StatelessWidget {
  final String? message;
  final VoidCallback onOpenAdministration;

  const _ServerReferentialWarningCard({
    required this.message,
    required this.onOpenAdministration,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMessage = message == null || message!.trim().isEmpty
        ? 'Aucun référentiel officiel actif n’est disponible côté serveur.'
        : message!.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 38),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Référentiel serveur non chargé',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'OpenIRN ne charge plus le référentiel embarqué dans l’application. Installe ou recharge le référentiel officiel aDRI depuis le serveur.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(effectiveMessage),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpenAdministration,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Ouvrir l’administration'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(subtitle),
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
                    onPressed: onPressed,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(buttonLabel),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(buttonLabel),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _AdministrationAuthenticationSource { server, localFallback, localOnly }

class _AdministrationAuthenticationData {
  final _AdministrationAuthenticationSource source;
  final String message;
  final List<AppUser> users;
  final String apiBaseUrl;
  final String tenantId;
  final String apiToken;

  const _AdministrationAuthenticationData({
    required this.source,
    required this.message,
    required this.users,
    this.apiBaseUrl = '',
    this.tenantId = '',
    this.apiToken = '',
  });

  _AdministrationAuthenticationData copyWith({
    _AdministrationAuthenticationSource? source,
    String? message,
    List<AppUser>? users,
    String? apiBaseUrl,
    String? tenantId,
    String? apiToken,
  }) {
    return _AdministrationAuthenticationData(
      source: source ?? this.source,
      message: message ?? this.message,
      users: users ?? this.users,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      tenantId: tenantId ?? this.tenantId,
      apiToken: apiToken ?? this.apiToken,
    );
  }

  String get sourceLabel {
    switch (source) {
      case _AdministrationAuthenticationSource.server:
        return 'Base centrale serveur';
      case _AdministrationAuthenticationSource.localFallback:
        return 'Secours hors ligne';
      case _AdministrationAuthenticationSource.localOnly:
        return 'Mode hors ligne';
    }
  }

  IconData get sourceIcon {
    switch (source) {
      case _AdministrationAuthenticationSource.server:
        return Icons.cloud_done_outlined;
      case _AdministrationAuthenticationSource.localFallback:
        return Icons.cloud_off_outlined;
      case _AdministrationAuthenticationSource.localOnly:
        return Icons.storage_outlined;
    }
  }
}

class _AdministrationAuthenticationDialog extends StatelessWidget {
  final String title;
  final String intro;
  final List<AppUser> users;
  final _AdministrationAuthenticationSource source;
  final String message;
  final IconData trailingIcon;

  const _AdministrationAuthenticationDialog({
    required this.title,
    required this.intro,
    required this.users,
    required this.source,
    required this.message,
    required this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceData = _AdministrationAuthenticationData(
      source: source,
      message: message,
      users: users,
    );
    final dialogMaxHeight = MediaQuery.sizeOf(context).height * 0.62;

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(title),
      content: ResponsiveDialogContent(
        maxWidth: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(intro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(sourceData.sourceIcon, size: 18),
                    label: Text(sourceData.sourceLabel),
                  ),
                  Chip(label: Text('${users.length} profil(s) autorisé(s)')),
                ],
              ),
              const SizedBox(height: 8),
              Text(message, style: theme.textTheme.bodySmall),
              const SizedBox(height: 14),
              Flexible(
                fit: FlexFit.loose,
                child: ListView.separated(
                  shrinkWrap: true,
                  primary: false,
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return Card.outlined(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(_initials(user))),
                        title: Text(
                          user.fullName.isNotEmpty ? user.fullName : user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(user.role.label),
                        trailing: Icon(trailingIcon),
                        onTap: () => Navigator.of(context).pop(user),
                      ),
                    );
                  },
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
      ],
    );
  }

  String _initials(AppUser user) {
    final parts = <String>[
      user.firstName.trim(),
      user.lastName.trim(),
    ].where((part) => part.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) {
      final fallback = user.email.trim().isNotEmpty
          ? user.email.trim()
          : user.id.trim();
      return fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase();
    }
    final initials = parts
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();
    return initials.isEmpty ? '?' : initials;
  }
}

class _AdministrationPinAuthenticationDialog extends StatefulWidget {
  final AppUser user;

  const _AdministrationPinAuthenticationDialog({required this.user});

  @override
  State<_AdministrationPinAuthenticationDialog> createState() =>
      _AdministrationPinAuthenticationDialogState();
}

class _AdministrationPinAuthenticationDialogState
    extends State<_AdministrationPinAuthenticationDialog> {
  final _pinController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _appendPinDigit(String digit) {
    final currentPin = _pinController.text;
    if (currentPin.length >= 32) {
      return;
    }

    setState(() {
      _pinController.text = '$currentPin$digit';
      _errorText = null;
    });
  }

  void _removePinDigit() {
    final currentPin = _pinController.text;
    if (currentPin.isEmpty) {
      return;
    }

    setState(() {
      _pinController.text = currentPin.substring(0, currentPin.length - 1);
      _errorText = null;
    });
  }

  void _clearPin() {
    if (_pinController.text.isEmpty) {
      return;
    }

    setState(() {
      _pinController.clear();
      _errorText = null;
    });
  }

  void _submit() {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() {
        _errorText = 'Saisis ton code personnel.';
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.fullName.isNotEmpty
        ? widget.user.fullName
        : widget.user.email;
    final useSecureMobilePinPad = shouldUseMobileKeyboardWorkaround(context);

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Authentification utilisateur'),
      content: ResponsiveDialogContent(
        maxWidth: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.isEmpty ? widget.user.id : displayName,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(widget.user.role.label),
              const SizedBox(height: 16),
              if (useSecureMobilePinPad)
                _AdministrationMobilePinPad(
                  pinLength: _pinController.text.length,
                  errorText: _errorText,
                  onDigit: _appendPinDigit,
                  onBackspace: _removePinDigit,
                  onClear: _clearPin,
                  onSubmit: _submit,
                )
              else
                TextField(
                  controller: _pinController,
                  autofocus: shouldAutofocusTextField(context),
                  obscureText: true,
                  keyboardType: safeKeyboardType(context, TextInputType.number),
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Code personnel',
                    helperText:
                        'Code initial serveur : 0000 si aucun code n’a encore été défini.',
                    errorText: _errorText,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() {
                        _errorText = null;
                      });
                    }
                  },
                  onSubmitted: (_) => _submit(),
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
        if (!useSecureMobilePinPad)
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.login_outlined),
            label: const Text('Ouvrir'),
          ),
      ],
    );
  }
}

class _AdministrationMobilePinPad extends StatelessWidget {
  final int pinLength;
  final String? errorText;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const _AdministrationMobilePinPad({
    required this.pinLength,
    required this.errorText,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayedDots = pinLength.clamp(0, 8);
    final semanticDigits = pinLength > 1 ? 'chiffres saisis' : 'chiffre saisi';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Code personnel', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(
          label: 'Code personnel, $pinLength $semanticDigits',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (
                  var index = 0;
                  index < 4 || index < displayedDots;
                  index++
                ) ...[
                  Icon(
                    index < pinLength ? Icons.circle : Icons.circle_outlined,
                    size: 14,
                    color: index < pinLength
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                  if (index < 3 || index + 1 < displayedDots)
                    const SizedBox(width: 12),
                ],
                if (pinLength > displayedDots) ...[
                  const SizedBox(width: 8),
                  Text(
                    '+${pinLength - displayedDots}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Code initial serveur : 0000 si aucun code n’a encore été défini.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.25,
          children: [
            for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
              OutlinedButton(
                onPressed: () => onDigit(digit),
                child: Text(digit),
              ),
            TextButton(
              onPressed: pinLength == 0 ? null : onClear,
              child: const Text('Effacer'),
            ),
            OutlinedButton(
              onPressed: () => onDigit('0'),
              child: const Text('0'),
            ),
            IconButton.outlined(
              onPressed: pinLength == 0 ? null : onBackspace,
              tooltip: 'Supprimer le dernier chiffre',
              icon: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.login_outlined),
          label: const Text('Ouvrir'),
        ),
      ],
    );
  }
}

class ReferentialCatalogScreen extends StatefulWidget {
  final IrnReferential referential;

  const ReferentialCatalogScreen({required this.referential, super.key});

  @override
  State<ReferentialCatalogScreen> createState() =>
      _ReferentialCatalogScreenState();
}

class _ReferentialCatalogScreenState extends State<ReferentialCatalogScreen> {
  final _service = const ReferentialCatalogService();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _query = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Référentiel aDRI IRN'),
      body: _ReferentialContent(
        referential: widget.referential,
        service: _service,
        query: _query,
        searchController: _searchController,
      ),
    );
  }
}

class _ReferentialContent extends StatelessWidget {
  final IrnReferential referential;
  final ReferentialCatalogService service;
  final TextEditingController searchController;
  final String query;

  const _ReferentialContent({
    required this.referential,
    required this.service,
    required this.searchController,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final scopes = service.criteriaCountByScope(referential);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(referential: referential),
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher dans le référentiel',
                hintText: 'Ex. RES-6, gouvernance, actif, portabilité...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        onPressed: searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _ScopeChips(scopes: scopes),
            const SizedBox(height: 12),
            for (final pillar in referential.pillars)
              _PillarExpansionTile(
                pillar: pillar,
                criteria: service.criteriaForPillar(
                  referential,
                  pillar.id,
                  query: query,
                ),
                initiallyExpanded: query.trim().isNotEmpty,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final IrnReferential referential;

  const _HeaderCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'aDRI IRN ${referential.version}',
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${referential.pillars.length} piliers · ${referential.criteria.length} critères',
            ),
            const SizedBox(height: 8),
            SelectableText('Source : ${referential.sourceUrl}'),
            const SizedBox(height: 4),
            Text('Licence : ${referential.license}'),
            if (referential.source.filePath.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Fichier : ${referential.source.filePath}'),
            ],
            if (referential.checksumSha256 != null &&
                referential.checksumSha256!.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText('SHA-256 : ${referential.checksumSha256}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScopeChips extends StatelessWidget {
  final Map<CriterionScope, int> scopes;

  const _ScopeChips({required this.scopes});

  @override
  Widget build(BuildContext context) {
    final entries = scopes.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          Chip(label: Text('${entry.key.label} : ${entry.value}')),
      ],
    );
  }
}

class _PillarExpansionTile extends StatelessWidget {
  final IrnPillar pillar;
  final List<IrnCriterion> criteria;
  final bool initiallyExpanded;

  const _PillarExpansionTile({
    required this.pillar,
    required this.criteria,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded && criteria.isNotEmpty,
        title: Text('${pillar.code} — ${pillar.label}'),
        subtitle: Text(
          '${criteria.length} critère${criteria.length > 1 ? 's' : ''}',
        ),
        children: [
          if (criteria.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(
                'Aucun critère ne correspond à la recherche dans ce pilier.',
              ),
            ),
          for (final criterion in criteria)
            ListTile(
              leading: CircleAvatar(
                child: Text(criterion.code.split('.').last),
              ),
              title: Text('${criterion.code} — ${criterion.label}'),
              subtitle: Text(
                'Portée : ${criterion.scope.label} · Réponse : ${criterion.answerMode}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CriterionDetailScreen(
                    pillar: pillar,
                    criterion: criterion,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger le référentiel',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
              'Vérifie que le terminal est autorisé et que le référentiel officiel est installé côté serveur.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
