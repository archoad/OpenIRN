import 'package:flutter/material.dart';

import '../../l10n/openirn_localizations.dart';
import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/models/tenant_info.dart';
import '../../domain/repositories/irn_referential_repository.dart';
import '../../domain/services/app_session_manager.dart';
import '../../domain/services/pin_policy.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/access_policy_service.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../about/about_screen.dart';
import '../admin/administration_screen.dart';
import '../campaigns/campaign_list_screen.dart';
import '../common/change_access_code_card.dart';
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
    AppSessionManager.instance.clearSession();
    _bootstrapFuture = _loadBootstrap();
  }

  Future<_ReferentialBootstrap> _loadBootstrap({
    bool resetTenantSelection = false,
  }) async {
    final configuration = resetTenantSelection
        ? await _syncConfigurationRepository.clearTenantSelection()
        : await _syncConfigurationRepository.loadConfiguration();

    if (!configuration.hasSelectedTenant) {
      AppSyncCoordinator.instance.stop();
      return _ReferentialBootstrap(
        referential: _emptyServerReferential(),
        configuration: configuration,
        referentialError: null,
        requiresTenantSelection: true,
        requiresDeviceEnrollment: false,
      );
    }

    if (!configuration.isConfigured) {
      AppSyncCoordinator.instance.stop();
      return _ReferentialBootstrap(
        referential: _emptyServerReferential(),
        configuration: configuration,
        referentialError: null,
        requiresTenantSelection: false,
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
        requiresTenantSelection: false,
        requiresDeviceEnrollment: false,
      );
    } catch (error) {
      AppSyncCoordinator.instance.stop();
      final errorMessage = error.toString();
      return _ReferentialBootstrap(
        referential: _emptyServerReferential(),
        configuration: configuration,
        referentialError: errorMessage,
        requiresTenantSelection: false,
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
        SnackBar(
          content: Text(
            context.tr(
              'home.about.referential_required',
              fallback:
                  'Le référentiel serveur doit être chargé avant d’ouvrir À propos.',
            ),
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
            return _ErrorState(
              error: context.tr(
                'home.error.missing_state',
                fallback: 'État d’accueil absent.',
              ),
            );
          }

          return _HomeContent(
            referential: bootstrap.referential,
            initialConfiguration: bootstrap.configuration,
            referentialError: bootstrap.referentialError,
            requiresTenantSelection: bootstrap.requiresTenantSelection,
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
  final bool requiresTenantSelection;
  final bool requiresDeviceEnrollment;

  const _ReferentialBootstrap({
    required this.referential,
    required this.configuration,
    required this.referentialError,
    required this.requiresTenantSelection,
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
  final bool requiresTenantSelection;
  final bool requiresDeviceEnrollment;
  final VoidCallback onConfigurationChanged;

  const _HomeContent({
    required this.referential,
    required this.initialConfiguration,
    required this.referentialError,
    required this.requiresTenantSelection,
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
        oldWidget.requiresTenantSelection != widget.requiresTenantSelection ||
        oldWidget.requiresDeviceEnrollment != widget.requiresDeviceEnrollment) {
      _syncConfigurationFuture = Future<SyncConfiguration>.value(
        widget.initialConfiguration,
      );
    }
  }

  Future<void> _openDeviceEnrollment() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!mounted) {
      return;
    }
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            DeviceEnrollmentScreen(initialTenantId: configuration.tenantId),
      ),
    );
    if (!mounted) {
      return;
    }
    if (enrolled == true || enrolled == false) {
      widget.onConfigurationChanged();
      setState(() {
        _syncConfigurationFuture = _syncConfigurationRepository
            .loadConfiguration();
      });
    }
  }

  Future<void> _chooseTenant() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    final result = await _apiClient.loadTenants(
      baseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: SyncConfiguration.defaultTenantId,
    );

    if (!mounted) {
      return;
    }

    if (!result.isAvailable || result.tenants.isEmpty) {
      _showForbidden('${result.title} — ${result.message}');
      return;
    }

    final selected = await showDialog<TenantInfo>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TenantSelectionDialog(
        tenants: result.tenants,
        selectedTenantId: configuration.tenantId,
      ),
    );

    if (selected == null || !mounted) {
      return;
    }

    final workspaceSelectedReason = context.tr(
      'home.session.workspace_selected',
      fallback: 'Espace de travail {workspace} sélectionné.',
      values: {'workspace': selected.displayName},
    );

    final updated = await _syncConfigurationRepository.saveConfiguration(
      configuration.copyWith(
        tenantId: selected.id,
        tenantDisplayName: selected.label,
        enabled: true,
        apiToken: '',
      ),
    );

    AppSessionManager.instance.clearSession(reason: workspaceSelectedReason);
    AppSyncCoordinator.instance.stop();

    if (!mounted) {
      return;
    }

    widget.onConfigurationChanged();
    setState(() {
      _syncConfigurationFuture = Future<SyncConfiguration>.value(updated);
    });
  }

  Future<void> _returnToTenantSelection() async {
    final returnWorkspaceSelectionReason = context.tr(
      'home.session.return_workspace_selection',
      fallback: 'Retour au choix de l’espace de travail.',
    );

    final updated = await _syncConfigurationRepository.clearTenantSelection();
    AppSessionManager.instance.clearSession(
      reason: returnWorkspaceSelectionReason,
    );
    AppSyncCoordinator.instance.stop();

    if (!mounted) {
      return;
    }

    widget.onConfigurationChanged();
    setState(() {
      _syncConfigurationFuture = Future<SyncConfiguration>.value(updated);
    });
  }

  void _showForbidden(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isGenericTenantLabel(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty || normalized == 'espace de travail';
  }

  String _firstBusinessTenantLabel(Iterable<String> candidates) {
    for (final candidate in candidates) {
      final label = candidate.trim();
      if (!_isGenericTenantLabel(label)) {
        return label;
      }
    }
    return '';
  }

  String _tenantLabelFromUsers(
    Iterable<AppUser> users, {
    String fallback = '',
  }) {
    return _firstBusinessTenantLabel(<String>[
      fallback,
      for (final user in users) user.tenantDisplayName,
      for (final user in users) user.tenantLabel,
    ]);
  }

  String _effectiveSessionTenantLabel({
    SyncConfiguration? configuration,
    required AppUser user,
  }) {
    return _firstBusinessTenantLabel(<String>[
      configuration?.tenantDisplayName ?? '',
      user.tenantDisplayName,
      user.tenantLabel,
      configuration?.tenantLabel ?? '',
    ]);
  }

  String _currentTenantName(SyncConfiguration? configuration) {
    final activeUser = AppSessionManager.instance.activeUser;
    return _firstBusinessTenantLabel(<String>[
      configuration?.tenantDisplayName ?? '',
      activeUser?.tenantDisplayName ?? '',
      activeUser?.tenantLabel ?? '',
      configuration?.tenantLabel ?? '',
    ]);
  }

  Future<void> _refreshConfigurationTenantLabel({
    required String tenantLabel,
    String tenantId = '',
  }) async {
    final label = tenantLabel.trim();
    if (_isGenericTenantLabel(label)) {
      return;
    }
    final current = await _syncConfigurationRepository.loadConfiguration();
    final updated = await _syncConfigurationRepository.saveConfiguration(
      current.copyWith(
        tenantId: tenantId.trim().isEmpty ? current.tenantId : tenantId.trim(),
        tenantDisplayName: label,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _syncConfigurationFuture = Future<SyncConfiguration>.value(updated);
    });
  }

  Future<void> _openCampaigns() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!mounted) {
      return;
    }
    if (widget.requiresDeviceEnrollment || !configuration.isConfigured) {
      _showForbidden(
        context.tr(
          'home.forbidden.enroll_before_campaigns',
          fallback:
              'Veuillez autoriser ce terminal avant d’ouvrir une campagne d’évaluation.',
        ),
      );
      return;
    }
    final activeUser = AppSessionManager.instance.activeUser;
    if (!AppSessionManager.instance.hasActiveSession || activeUser == null) {
      _showForbidden(
        context.tr(
          'home.forbidden.unlock_before_campaigns',
          fallback:
              'Veuillez déverrouiller OpenIRN avec votre profil et votre code personnel avant d’ouvrir une campagne.',
        ),
      );
      return;
    }
    if (!_accessPolicy.can(activeUser, OpenIrnPermission.viewCampaignList)) {
      _showForbidden(
        context.tr(
          'home.forbidden.campaigns_role',
          fallback: 'Votre profil ne permet pas d’ouvrir les campagnes.',
        ),
      );
      return;
    }
    if (!_hasServerReferential) {
      _showForbidden(
        context.tr(
          'home.forbidden.install_referential_before_campaigns',
          fallback:
              'Veuillez installer ou recharger le référentiel officiel aDRI depuis l’administration avant d’ouvrir une campagne.',
        ),
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
        context.tr(
          'home.forbidden.unlock_before_referential',
          fallback:
              'Veuillez déverrouiller OpenIRN avec votre profil et votre code personnel avant d’ouvrir le référentiel.',
        ),
      );
      return;
    }
    if (!_accessPolicy.can(
      activeUser,
      OpenIrnPermission.viewReferentialCatalog,
    )) {
      _showForbidden(
        context.tr(
          'home.forbidden.referential_role',
          fallback: 'Votre profil ne permet pas de consulter le référentiel.',
        ),
      );
      return;
    }
    if (!_hasServerReferential) {
      _showForbidden(
        context.tr(
          'home.forbidden.referential_not_loaded',
          fallback:
              'Le référentiel officiel n’est pas encore chargé depuis le serveur.',
        ),
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
        context.tr(
          'home.forbidden.enroll_before_admin',
          fallback:
              'Veuillez autoriser ce terminal avant d’ouvrir l’administration.',
        ),
      );
      return;
    }

    final activeUser = AppSessionManager.instance.activeUser;
    if (!AppSessionManager.instance.hasActiveSession || activeUser == null) {
      _showForbidden(
        context.tr(
          'home.forbidden.unlock_before_admin',
          fallback:
              'Veuillez déverrouiller OpenIRN avec votre profil et votre code personnel avant d’ouvrir l’administration.',
        ),
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
    final selectedConfiguration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!mounted) {
      return;
    }
    if (!selectedConfiguration.hasSelectedTenant) {
      _showForbidden(
        context.tr(
          'home.forbidden.choose_workspace_before_unlock',
          fallback:
              'Veuillez d’abord choisir un espace de travail avant d’ouvrir une session.',
        ),
      );
      return;
    }
    if (!selectedConfiguration.isConfigured) {
      _showForbidden(
        context.tr(
          'home.forbidden.enroll_workspace_before_unlock',
          fallback:
              'Veuillez autoriser ce terminal dans cet espace de travail avant d’ouvrir une session.',
        ),
      );
      return;
    }

    final authenticationData = await _loadAuthenticatableUsers(
      configuration: selectedConfiguration,
    );
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
      _showForbidden(
        context.tr(
          'home.forbidden.no_active_user',
          fallback:
              'Aucun profil utilisateur actif n’est disponible pour cet espace de travail.',
        ),
      );
      return;
    }

    final selectedUser = await showDialog<AppUser>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdministrationAuthenticationDialog(
        title: context.tr(
          'home.unlock.dialog.title',
          fallback: 'Déverrouiller OpenIRN',
        ),
        intro: context.tr(
          'home.unlock.dialog.intro',
          fallback:
              'Veuillez choisir votre profil dans l’espace de travail {workspace}, puis saisir votre code personnel.',
          values: {'workspace': authenticationData.tenantLabel},
        ),
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

    final authenticatedUser =
        AppSessionManager.instance.activeUser ?? selectedUser;
    final effectiveTenantLabel = _tenantLabelFromUsers(<AppUser>[
      authenticatedUser,
      selectedUser,
    ], fallback: authenticationData.tenantDisplayName);
    await _refreshConfigurationTenantLabel(
      tenantLabel: effectiveTenantLabel,
      tenantId: AppSessionManager.instance.tenantId.isNotEmpty
          ? AppSessionManager.instance.tenantId
          : authenticationData.tenantId,
    );
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'home.session.opened_user',
            fallback: 'Session ouverte : {user}',
            values: {'user': selectedUser.displayName},
          ),
        ),
      ),
    );
    widget.onConfigurationChanged();
    setState(() {
      _syncConfigurationFuture = _syncConfigurationRepository
          .loadConfiguration();
    });
  }

  Future<void> _lockSession() async {
    final lockedManuallyReason = context.tr(
      'home.session.locked_manually',
      fallback: 'Session verrouillée manuellement.',
    );
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

    AppSessionManager.instance.clearSession(reason: lockedManuallyReason);
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
        context.tr(
          'home.forbidden.server_auth_required',
          fallback:
              'Authentification serveur obligatoire pour accéder à l’administration.',
        ),
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

    var result = await _apiClient.verifyUserPin(
      baseUrl: authenticationData.apiBaseUrl,
      tenantId: authenticationData.tenantId,
      apiToken: authenticationData.apiToken,
      userId: user.id,
      pin: pin,
    );

    if (!mounted) {
      return result.isAccepted;
    }

    if (result.mustChangePin) {
      final newPin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _InitialPinChangeDialog(user: user),
      );
      if (newPin == null || !mounted) {
        return false;
      }
      result = await _apiClient.verifyUserPin(
        baseUrl: authenticationData.apiBaseUrl,
        tenantId: authenticationData.tenantId,
        apiToken: authenticationData.apiToken,
        userId: user.id,
        pin: pin,
        newPin: newPin,
      );
      if (!mounted) {
        return result.isAccepted;
      }
    }

    if (!result.isAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.title} — ${result.message}')),
      );
      return false;
    }

    return true;
  }

  Future<_AdministrationAuthenticationData> _loadAuthenticatableUsers({
    SyncConfiguration? configuration,
  }) async {
    configuration ??= await _syncConfigurationRepository.loadConfiguration();

    if (widget.requiresTenantSelection) {
      return _AdministrationAuthenticationData(
        source: _AdministrationAuthenticationSource.localOnly,
        message: OpenIrnLocalizations.instance.tr(
          'home.auth.choose_workspace_first',
          fallback:
              'Veuillez d’abord choisir un espace de travail avant d’ouvrir une session OpenIRN.',
        ),
        users: const <AppUser>[],
      );
    }

    if (widget.requiresDeviceEnrollment || !configuration.isConfigured) {
      return _AdministrationAuthenticationData(
        source: _AdministrationAuthenticationSource.localOnly,
        message: OpenIrnLocalizations.instance.tr(
          'home.auth.device_not_authorized',
          fallback:
              'Terminal non autorisé : veuillez autoriser ce terminal avant d’accéder aux fonctions protégées.',
        ),
        users: const <AppUser>[],
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
          message: OpenIrnLocalizations.instance.tr(
            'home.auth.server_users_message',
            fallback:
                '{message} Veuillez sélectionner votre identité puis saisir votre code personnel.',
            values: {'message': centralUsers.message},
          ),
          users: centralUsers.users,
          apiBaseUrl: configuration.apiBaseUrl,
          tenantId: centralUsers.tenantId.trim().isNotEmpty
              ? centralUsers.tenantId
              : configuration.tenantId,
          tenantDisplayName: _tenantLabelFromUsers(
            centralUsers.users,
            fallback: configuration.tenantDisplayName,
          ),
          apiToken: configuration.apiToken,
        );
      }

      return _AdministrationAuthenticationData(
        source: _AdministrationAuthenticationSource.localFallback,
        message: OpenIrnLocalizations.instance.tr(
          'home.auth.unavailable',
          fallback:
              '{title} — authentification indisponible. Veuillez réessayer lorsque le serveur OpenIRN répond.',
          values: {'title': centralUsers.title},
        ),
        users: const <AppUser>[],
      );
    }

    return _AdministrationAuthenticationData(
      source: _AdministrationAuthenticationSource.localOnly,
      message: OpenIrnLocalizations.instance.tr(
        'home.auth.device_not_authorized',
        fallback:
            'Terminal non autorisé : veuillez autoriser ce terminal avant d’accéder aux fonctions protégées.',
      ),
      users: const <AppUser>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncConfiguration>(
      future: _syncConfigurationFuture,
      builder: (context, snapshot) {
        final configuration = snapshot.data;
        final isConfigured = configuration?.isConfigured ?? false;
        final currentTenantName = _currentTenantName(configuration);
        final currentTenantSentence = currentTenantName.isEmpty
            ? context.tr(
                'home.workspace.current_selected',
                fallback: 'Espace actuel : espace sélectionné.',
              )
            : context.tr(
                'home.workspace.current_named',
                fallback: 'Espace actuel : « {workspace} ».',
                values: {'workspace': currentTenantName},
              );
        final currentTenantPhrase = currentTenantName.isEmpty
            ? context.tr(
                'home.workspace.selected_phrase',
                fallback: 'l’espace de travail sélectionné',
              )
            : context.tr(
                'home.workspace.named_phrase',
                fallback: 'l’espace de travail « {workspace} »',
                values: {'workspace': currentTenantName},
              );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.requiresTenantSelection ||
                    configuration?.hasSelectedTenant != true)
                  _HomeActionCard(
                    icon: Icons.account_tree_outlined,
                    title: 'Choisir un espace de travail',
                    subtitle:
                        'Sélectionner l’espace de travail OpenIRN avant de choisir un utilisateur ou d’autoriser ce terminal.',
                    buttonLabel: 'Choisir',
                    onPressed: _chooseTenant,
                  )
                else if (widget.requiresDeviceEnrollment || !isConfigured) ...[
                  _HomeActionCard(
                    icon: Icons.phonelink_lock_outlined,
                    title: 'Autoriser ce terminal',
                    subtitle: context.tr(
                      'home.action.enroll.subtitle',
                      fallback:
                          'Autoriser ce poste dans {workspace} avant d’accéder aux campagnes et à l’administration.',
                      values: {'workspace': currentTenantPhrase},
                    ),
                    buttonLabel: 'Appairer',
                    onPressed: _openDeviceEnrollment,
                  ),
                  const SizedBox(height: 12),
                  _HomeActionCard(
                    icon: Icons.arrow_back_outlined,
                    title: 'Retour au choix de l’espace de travail',
                    subtitle:
                        'Changer d’espace de travail sans autoriser ce terminal dans l’espace actuellement sélectionné.',
                    buttonLabel: 'Retour',
                    onPressed: _returnToTenantSelection,
                  ),
                ] else if (!AppSessionManager.instance.hasActiveSession ||
                    AppSessionManager.instance.activeUser == null) ...[
                  _HomeActionCard(
                    icon: Icons.lock_open_outlined,
                    title: 'Déverrouiller OpenIRN',
                    subtitle:
                        'Ouvrir une session avec votre profil et votre code personnel.',
                    buttonLabel: 'Déverrouiller',
                    onPressed: _unlockSession,
                  ),
                  const SizedBox(height: 12),
                  _HomeActionCard(
                    icon: Icons.swap_horiz_outlined,
                    title: 'Changer d’espace de travail',
                    subtitle: context.tr(
                      'home.action.change_workspace.subtitle',
                      fallback:
                          '{current} Revenir au choix de l’espace de travail OpenIRN avant d’ouvrir une session.',
                      values: {'current': currentTenantSentence},
                    ),
                    buttonLabel: 'Changer',
                    onPressed: _chooseTenant,
                  ),
                ] else ...[
                  _SessionStatusCard(
                    user: AppSessionManager.instance.activeUser!,
                    tenantLabel: _effectiveSessionTenantLabel(
                      configuration: configuration,
                      user: AppSessionManager.instance.activeUser!,
                    ),
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
                      subtitle: "Ouvrir une campagne d'évaluation",
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
                      subtitle: 'Accéder aux opérations d\'administration.',
                      buttonLabel: 'Administrer',
                      onPressed: _openAdministration,
                    )
                  else
                    const ChangeAccessCodeCard(
                      title: 'Administration',
                      subtitle:
                          'Changer votre code d’accès personnel sans passer par un administrateur.',
                      buttonLabel: 'Changer mon code',
                      elevatedButton: true,
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
  final String tenantLabel;
  final DateTime? expiresAt;
  final DateTime? idleExpiresAt;
  final Future<void> Function() onLock;

  const _SessionStatusCard({
    required this.user,
    required this.tenantLabel,
    required this.expiresAt,
    required this.idleExpiresAt,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = user.displayName.trim();
    final effectiveTenantLabel = tenantLabel.trim();
    final expirationText = expiresAt == null
        ? context.tr(
            'home.session.expiration_unknown',
            fallback: 'Expiration serveur non communiquée',
          )
        : context.tr(
            'home.session.expires_at',
            fallback: 'Expire à {time}',
            values: {'time': _formatSessionExpiration(expiresAt!.toLocal())},
          );
    final idleText = idleExpiresAt == null
        ? context.tr(
            'home.session.idle_unknown',
            fallback: 'Verrouillage automatique après inactivité',
          )
        : context.tr(
            'home.session.idle_expires_at',
            fallback: 'Verrouillage auto à {time} en l’absence d’activité',
            values: {
              'time': _formatSessionExpiration(idleExpiresAt!.toLocal()),
            },
          );
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
              Text(
                context.tr('home.session.open', fallback: 'Session ouverte'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text('$displayName — ${user.role.label}'),
              if (effectiveTenantLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'home.session.workspace',
                    fallback: 'Espace de travail : {workspace}',
                    values: {'workspace': effectiveTenantLabel},
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                    label: Text(
                      context.tr('home.session.lock', fallback: 'Verrouiller'),
                    ),
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
                    label: Text(
                      context.tr('home.session.lock', fallback: 'Verrouiller'),
                    ),
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
        ? context.tr(
            'home.server_referential.default_error',
            fallback:
                'Aucun référentiel officiel actif n’est disponible côté serveur.',
          )
        : context.trText(message!.trim());

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
                        context.tr(
                          'home.server_referential.title',
                          fallback: 'Référentiel serveur non chargé',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'home.server_referential.description',
                          fallback:
                              'OpenIRN ne charge plus le référentiel embarqué dans l’application. Installe ou recharge le référentiel officiel aDRI depuis le serveur.',
                        ),
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
                label: Text(
                  context.tr(
                    'home.server_referential.open_admin',
                    fallback: 'Ouvrir l’administration',
                  ),
                ),
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
              Text(
                context.trText(title),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(context.trText(subtitle)),
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
                    label: Text(context.trText(buttonLabel)),
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
                    label: Text(context.trText(buttonLabel)),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TenantSelectionDialog extends StatelessWidget {
  final List<TenantInfo> tenants;
  final String selectedTenantId;

  const _TenantSelectionDialog({
    required this.tenants,
    required this.selectedTenantId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogMaxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        context.tr(
          'home.tenant_dialog.title',
          fallback: 'Choisir l’espace de travail',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 720,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'home.tenant_dialog.intro',
                  fallback:
                      'Veuillez d’abord sélectionner l’espace de travail. OpenIRN affichera ensuite uniquement les utilisateurs rattachés à cet espace.',
                ),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Flexible(
                fit: FlexFit.loose,
                child: ListView.separated(
                  shrinkWrap: true,
                  primary: false,
                  itemCount: tenants.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final tenant = tenants[index];
                    final selected = tenant.id == selectedTenantId;
                    return Card.outlined(
                      child: ListTile(
                        leading: Icon(
                          tenant.isDefault
                              ? Icons.home_work_outlined
                              : Icons.business_outlined,
                        ),
                        title: Text(tenant.label),
                        subtitle: Text(
                          context.tr(
                            'home.tenant_dialog.summary',
                            fallback:
                                '{users} utilisateur(s) actif(s) · {campaigns} campagne(s)',
                            values: {
                              'users': tenant.activeUserCount,
                              'campaigns': tenant.campaignCount,
                            },
                          ),
                        ),
                        trailing: selected
                            ? Chip(
                                label: Text(
                                  context.tr(
                                    'home.tenant_dialog.current',
                                    fallback: 'Actuel',
                                  ),
                                ),
                              )
                            : const Icon(Icons.arrow_forward),
                        onTap: () => Navigator.of(context).pop(tenant),
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
          child: Text(context.tr('common.cancel', fallback: 'Annuler')),
        ),
      ],
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
  final String tenantDisplayName;
  final String apiToken;

  const _AdministrationAuthenticationData({
    required this.source,
    required this.message,
    required this.users,
    this.apiBaseUrl = '',
    this.tenantId = '',
    this.tenantDisplayName = '',
    this.apiToken = '',
  });

  _AdministrationAuthenticationData copyWith({
    _AdministrationAuthenticationSource? source,
    String? message,
    List<AppUser>? users,
    String? apiBaseUrl,
    String? tenantId,
    String? tenantDisplayName,
    String? apiToken,
  }) {
    return _AdministrationAuthenticationData(
      source: source ?? this.source,
      message: message ?? this.message,
      users: users ?? this.users,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      tenantId: tenantId ?? this.tenantId,
      tenantDisplayName: tenantDisplayName ?? this.tenantDisplayName,
      apiToken: apiToken ?? this.apiToken,
    );
  }

  String get tenantLabel {
    final label = tenantDisplayName.trim();
    return label.isEmpty ? 'Espace de travail' : label;
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
      title: Text(context.trText(title)),
      content: ResponsiveDialogContent(
        maxWidth: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.trText(intro), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(sourceData.sourceIcon, size: 18),
                    label: Text(context.trText(sourceData.sourceLabel)),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'home.auth_dialog.authorized_profiles',
                        fallback: '{count} profil(s) autorisé(s)',
                        values: {'count': users.length},
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(context.trText(message), style: theme.textTheme.bodySmall),
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
          child: Text(context.tr('common.cancel', fallback: 'Annuler')),
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
          : user.displayName.trim();
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
        _errorText = context.tr(
          'home.pin.required',
          fallback: 'Veuillez saisir votre code personnel.',
        );
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
      title: Text(
        context.tr(
          'home.pin_dialog.title',
          fallback: 'Authentification utilisateur',
        ),
      ),
      content: ResponsiveDialogContent(
        maxWidth: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.isEmpty
                    ? context.tr(
                        'home.pin_dialog.unnamed_user',
                        fallback: 'Utilisateur sans nom',
                      )
                    : displayName,
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
                    labelText: context.tr(
                      'home.pin.label',
                      fallback: 'Code personnel',
                    ),
                    helperText: context.tr(
                      'home.pin.initial_code_help',
                      fallback:
                          'Code initial serveur : 0000 si aucun code n’a encore été défini.',
                    ),
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
          child: Text(context.tr('common.cancel', fallback: 'Annuler')),
        ),
        if (!useSecureMobilePinPad)
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.login_outlined),
            label: Text(context.tr('common.open', fallback: 'Ouvrir')),
          ),
      ],
    );
  }
}

class _InitialPinChangeDialog extends StatefulWidget {
  final AppUser user;

  const _InitialPinChangeDialog({required this.user});

  @override
  State<_InitialPinChangeDialog> createState() =>
      _InitialPinChangeDialogState();
}

class _InitialPinChangeDialogState extends State<_InitialPinChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  @override
  void dispose() {
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(_newPinController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(context.tr('home.pin_change_required.title')),
      content: ResponsiveDialogContent(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'home.pin_change_required.message',
                  values: {'user': widget.user.displayName},
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPinController,
                autofocus: shouldAutofocusTextField(context),
                obscureText: true,
                keyboardType: safeKeyboardType(
                  context,
                  TextInputType.visiblePassword,
                ),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.tr('common.access_code.new'),
                  helperText: context.tr('home.pin_change_required.helper'),
                  prefixIcon: const Icon(Icons.password_outlined),
                ),
                validator: (value) {
                  final pin = value?.trim() ?? '';
                  if (pin.length < 4) {
                    return context.tr('common.access_code.too_short');
                  }
                  if (pin.length > 32) {
                    return context.tr('common.access_code.too_long');
                  }
                  if (isPredictableOpenIrnPin(pin)) {
                    return context.tr('common.access_code.too_predictable');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPinController,
                obscureText: true,
                keyboardType: safeKeyboardType(
                  context,
                  TextInputType.visiblePassword,
                ),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.tr('common.access_code.confirm'),
                  prefixIcon: const Icon(Icons.done_all_outlined),
                ),
                validator: (value) =>
                    (value?.trim() ?? '') != _newPinController.text.trim()
                    ? context.tr('common.access_code.confirm_mismatch')
                    : null,
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
          icon: const Icon(Icons.lock_reset_outlined),
          label: Text(context.tr('common.action.save')),
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
    final semanticDigits = pinLength > 1
        ? context.tr(
            'home.pin.semantic_digits_plural',
            fallback: 'chiffres saisis',
          )
        : context.tr(
            'home.pin.semantic_digits_singular',
            fallback: 'chiffre saisi',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('home.pin.label', fallback: 'Code personnel'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Semantics(
          label: context.tr(
            'home.pin.semantic_label',
            fallback: 'Code personnel, {count} {digits}',
            values: {'count': pinLength, 'digits': semanticDigits},
          ),
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
          context.tr(
            'home.pin.initial_code_help',
            fallback:
                'Code initial serveur : 0000 si aucun code n’a encore été défini.',
          ),
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
              child: Text(context.tr('common.clear', fallback: 'Effacer')),
            ),
            OutlinedButton(
              onPressed: () => onDigit('0'),
              child: const Text('0'),
            ),
            IconButton.outlined(
              onPressed: pinLength == 0 ? null : onBackspace,
              tooltip: context.tr(
                'home.pin.backspace',
                fallback: 'Supprimer le dernier chiffre',
              ),
              icon: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.login_outlined),
          label: Text(context.tr('common.open', fallback: 'Ouvrir')),
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
                labelText: context.tr(
                  'referential_catalog.search.label',
                  fallback: 'Rechercher dans le référentiel',
                ),
                hintText: context.tr(
                  'referential_catalog.search.hint',
                  fallback: 'Ex. RES-6, gouvernance, actif, portabilité...',
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr(
                          'common.clear',
                          fallback: 'Effacer',
                        ),
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
              context.tr(
                'referential_catalog.header.counts',
                fallback: '{pillars} piliers · {criteria} critères',
                values: {
                  'pillars': referential.pillars.length,
                  'criteria': referential.criteria.length,
                },
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              context.tr(
                'referential_catalog.header.source',
                fallback: 'Source : {source}',
                values: {'source': referential.sourceUrl},
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'referential_catalog.header.license',
                fallback: 'Licence : {license}',
                values: {'license': referential.license},
              ),
            ),
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
          Chip(
            label: Text('${context.trText(entry.key.label)} : ${entry.value}'),
          ),
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
          context.tr(
            criteria.length > 1
                ? 'referential_catalog.pillar.criteria_plural'
                : 'referential_catalog.pillar.criteria_singular',
            fallback: criteria.length > 1
                ? '{count} critères'
                : '{count} critère',
            values: {'count': criteria.length},
          ),
        ),
        children: [
          if (criteria.isEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                context.tr(
                  'referential_catalog.pillar.no_match',
                  fallback:
                      'Aucun critère ne correspond à la recherche dans ce pilier.',
                ),
              ),
            ),
          for (final criterion in criteria)
            ListTile(
              leading: CircleAvatar(
                child: Text(criterion.code.split('.').last),
              ),
              title: Text('${criterion.code} — ${criterion.label}'),
              subtitle: Text(
                context.tr(
                  'referential_catalog.criterion.subtitle',
                  fallback: 'Portée : {scope} · Réponse : {answerMode}',
                  values: {
                    'scope': context.trText(criterion.scope.label),
                    'answerMode': criterion.answerMode,
                  },
                ),
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
              context.tr(
                'referential_catalog.error.title',
                fallback: 'Impossible de charger le référentiel',
              ),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text(
              context.tr(
                'referential_catalog.error.help',
                fallback:
                    'Veuillez vérifier que le terminal est autorisé et que le référentiel officiel est disponible.',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
