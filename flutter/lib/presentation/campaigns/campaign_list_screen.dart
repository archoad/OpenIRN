import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/assessment_quality_service.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../assessment/assessment_screen.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class CampaignListScreen extends StatefulWidget {
  final IrnReferential referential;

  const CampaignListScreen({required this.referential, super.key});

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  final _campaignRepository = const LocalCampaignRepository();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _sessionRepository = const LocalSessionRepository();
  final _syncConfigurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _scoringService = const OfficialRnrScoringService();
  final _qualityService = const AssessmentQualityService();
  final _appSyncCoordinator = AppSyncCoordinator.instance;

  late Future<_CampaignListState> _campaignsFuture;
  int _lastAppliedSyncSerial = 0;

  @override
  void initState() {
    super.initState();
    _campaignsFuture = _loadCampaigns();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
  }

  @override
  void dispose() {
    _appSyncCoordinator.removeListener(_handleBackgroundSyncUpdate);
    super.dispose();
  }

  void _handleBackgroundSyncUpdate() {
    final serial = _appSyncCoordinator.changeSerial;
    if (!mounted || serial == _lastAppliedSyncSerial) {
      return;
    }
    _lastAppliedSyncSerial = serial;
    _refresh();
  }

  Future<_CampaignListState> _loadCampaigns() async {
    final campaigns = await _campaignRepository.loadCampaigns(
      referentialId: widget.referential.id,
    );

    final enriched = <_CampaignWithSummary>[];
    for (final campaign in campaigns) {
      final criterionAnswers = await _assessmentRepository.loadCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      final summary = _scoringService.computeSummary(
        widget.referential,
        answers,
      );
      final qualityReport = _qualityService.buildReport(
        referential: widget.referential,
        criterionAnswers: criterionAnswers,
        campaign: campaign,
      );
      enriched.add(
        _CampaignWithSummary(
          campaign: campaign,
          criterionAnswers: criterionAnswers,
          answers: answers,
          summary: summary,
          qualityReport: qualityReport,
        ),
      );
    }
    return _CampaignListState(campaigns: enriched);
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _campaignsFuture = _loadCampaigns();
    });
    await _campaignsFuture;
  }

  void _showForbidden(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCampaign(LocalCampaign campaign) async {
    final authenticatedUser = await _authenticateUserForCampaign(campaign);
    if (authenticatedUser == null || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentScreen(
          referential: widget.referential,
          campaign: campaign,
          activeUser: authenticatedUser,
        ),
      ),
    );
    await _refresh();
  }

  Future<AppUser?> _authenticateUserForCampaign(LocalCampaign campaign) async {
    final authenticationData = await _loadAuthenticatableUsers();
    if (!mounted) {
      return null;
    }

    final selectableUsers = authenticationData.users
        .where((user) => user.active)
        .toList(growable: false);
    if (selectableUsers.isEmpty) {
      _showForbidden(
        'Aucun utilisateur actif n’est disponible pour ouvrir cette campagne.',
      );
      return null;
    }

    final selectedUser = await showDialog<AppUser>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CampaignAuthenticationDialog(
        campaign: campaign,
        users: selectableUsers,
        source: authenticationData.source,
        message: authenticationData.message,
      ),
    );

    if (selectedUser == null) {
      return null;
    }

    final verified = await _verifySelectedUserForCampaign(
      authenticationData: authenticationData,
      user: selectedUser,
    );
    if (!verified) {
      return null;
    }

    await _sessionRepository.setActiveUser(selectedUser.id);
    return selectedUser;
  }

  Future<bool> _verifySelectedUserForCampaign({
    required _CampaignAuthenticationData authenticationData,
    required AppUser user,
  }) async {
    if (authenticationData.source != _CampaignAuthenticationSource.server) {
      _showForbidden(
        'Authentification serveur obligatoire pour ouvrir une campagne.',
      );
      return false;
    }

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PinAuthenticationDialog(user: user),
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

  Future<_CampaignAuthenticationData> _loadAuthenticatableUsers() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();

    if (!configuration.isConfigured) {
      return const _CampaignAuthenticationData(
        source: _CampaignAuthenticationSource.localOnly,
        message:
            'Terminal non autorisé : appaire ce terminal avant d’ouvrir une campagne.',
        users: <AppUser>[],
      );
    }

    final centralUsers = await _apiClient.loadUsers(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    if (centralUsers.hasUsers) {
      return _CampaignAuthenticationData(
        source: _CampaignAuthenticationSource.server,
        message:
            '${centralUsers.message} Sélectionne ton identité puis saisis ton code personnel.',
        users: centralUsers.users,
        apiBaseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );
    }

    return _CampaignAuthenticationData(
      source: _CampaignAuthenticationSource.localFallback,
      message:
          '${centralUsers.title} — ${centralUsers.message}. Aucun utilisateur local de secours n’est disponible.',
      users: const <AppUser>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Campagnes'),
      body: FutureBuilder<_CampaignListState>(
        future: _campaignsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final state = snapshot.data;
          final campaigns = state?.campaigns ?? <_CampaignWithSummary>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeaderCard(referential: widget.referential),
                  const SizedBox(height: 12),
                  if (campaigns.isEmpty)
                    const _NoCampaignState()
                  else
                    for (final campaign in campaigns)
                      _CampaignCard(
                        entry: campaign,
                        onOpen: () => _openCampaign(campaign.campaign),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _CampaignAuthenticationSource { server, localFallback, localOnly }

class _CampaignAuthenticationData {
  final _CampaignAuthenticationSource source;
  final String message;
  final List<AppUser> users;
  final String apiBaseUrl;
  final String tenantId;
  final String apiToken;

  const _CampaignAuthenticationData({
    required this.source,
    required this.message,
    required this.users,
    this.apiBaseUrl = '',
    this.tenantId = '',
    this.apiToken = '',
  });

  _CampaignAuthenticationData copyWith({
    _CampaignAuthenticationSource? source,
    String? message,
    List<AppUser>? users,
    String? apiBaseUrl,
    String? tenantId,
    String? apiToken,
  }) {
    return _CampaignAuthenticationData(
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
      case _CampaignAuthenticationSource.server:
        return 'Base centrale serveur';
      case _CampaignAuthenticationSource.localFallback:
        return 'Secours hors ligne';
      case _CampaignAuthenticationSource.localOnly:
        return 'Mode hors ligne';
    }
  }

  IconData get sourceIcon {
    switch (source) {
      case _CampaignAuthenticationSource.server:
        return Icons.cloud_done_outlined;
      case _CampaignAuthenticationSource.localFallback:
        return Icons.cloud_off_outlined;
      case _CampaignAuthenticationSource.localOnly:
        return Icons.storage_outlined;
    }
  }
}

class _CampaignAuthenticationDialog extends StatelessWidget {
  final LocalCampaign campaign;
  final List<AppUser> users;
  final _CampaignAuthenticationSource source;
  final String message;

  const _CampaignAuthenticationDialog({
    required this.campaign,
    required this.users,
    required this.source,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceData = _CampaignAuthenticationData(
      source: source,
      message: message,
      users: users,
    );
    final dialogMaxHeight = MediaQuery.sizeOf(context).height * 0.62;

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Sélection de l’utilisateur'),
      content: ResponsiveDialogContent(
        maxWidth: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: dialogMaxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Campagne : ${campaign.name}',
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(sourceData.sourceIcon, size: 18),
                    label: Text(sourceData.sourceLabel),
                  ),
                  Chip(label: Text('${users.length} utilisateur(s) actif(s)')),
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.email.isEmpty ? user.id : user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(user.role.label),
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.login_outlined),
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

class _PinAuthenticationDialog extends StatefulWidget {
  final AppUser user;

  const _PinAuthenticationDialog({required this.user});

  @override
  State<_PinAuthenticationDialog> createState() =>
      _PinAuthenticationDialogState();
}

class _PinAuthenticationDialogState extends State<_PinAuthenticationDialog> {
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
                _MobilePinPad(
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

class _MobilePinPad extends StatelessWidget {
  final int pinLength;
  final String? errorText;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const _MobilePinPad({
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

class _CampaignListState {
  final List<_CampaignWithSummary> campaigns;

  const _CampaignListState({required this.campaigns});
}

class _CampaignWithSummary {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final Map<String, IrnAnswer> answers;
  final IrnScoreSummary summary;
  final AssessmentQualityReport qualityReport;

  const _CampaignWithSummary({
    required this.campaign,
    required this.criterionAnswers,
    required this.answers,
    required this.summary,
    required this.qualityReport,
  });
}

class _HeaderCard extends StatelessWidget {
  final IrnReferential referential;

  const _HeaderCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.folder_copy_outlined, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Campagnes OpenIRN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Référentiel : ${referential.id} · ${referential.version}',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Une campagne regroupe une saisie R / NR, sa synthèse, son contrôle qualité, '
                    'son export JSON et maintenant un statut de workflow.',
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(Icons.login_outlined, size: 18),
                        label: Text(
                          'Authentification à l’ouverture de la campagne',
                        ),
                      ),
                      Chip(label: Text('Aucune session active sur cette page')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final _CampaignWithSummary entry;
  final VoidCallback onOpen;

  const _CampaignCard({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final campaign = entry.campaign;
    final summary = entry.summary;
    final qualityReport = entry.qualityReport;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (campaign.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(campaign.description),
                      ],
                      if (campaign.information.systemName
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'SI : ${campaign.information.systemName}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (campaign
                              .information
                              .projectDirectorFullName
                              .isNotEmpty ||
                          campaign.information.projectDirectorEmail
                              .trim()
                              .isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Directeur projet : ${_projectDirectorLabel(campaign.information)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  summary.formattedOfficialScore,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: summary.officialScore == null
                  ? 0
                  : summary.officialScore! / 100,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(campaign.status.label),
                ),
                Chip(
                  label: Text(
                    'Cotés : ${summary.answeredCriteria}/${summary.totalCriteria}',
                  ),
                ),
                Chip(label: Text('R : ${summary.resilientCriteria}')),
                Chip(label: Text('NR : ${summary.nonResilientCriteria}')),
                Chip(
                  label: Text(
                    'Complétude : ${(summary.completionRate * 100).toStringAsFixed(0)} %',
                  ),
                ),
                Chip(label: Text('Maj : ${_formatDate(campaign.updatedAt)}')),
                Chip(
                  avatar: Icon(
                    qualityReport.isCampaignInformationComplete
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                  ),
                  label: Text(
                    qualityReport.isCampaignInformationComplete
                        ? 'Infos campagne OK'
                        : 'Infos manquantes : ${qualityReport.missingCampaignInformationCount}',
                  ),
                ),
                if (campaign.isReadOnly)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 18),
                    label: Text('Lecture seule'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              campaign.status.helperText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.login_outlined),
                label: const Text('Ouvrir'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _projectDirectorLabel(CampaignInformation information) {
    final name = information.projectDirectorFullName;
    final email = information.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name <$email>';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return 'non renseigné';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _NoCampaignState extends StatelessWidget {
  const _NoCampaignState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.folder_off_outlined, size: 44),
            SizedBox(height: 12),
            Text('Aucune campagne disponible.'),
            SizedBox(height: 6),
            Text(
              'Utilise le menu ⋮ puis “Gérer les campagnes” pour créer une campagne.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text('Impossible de charger les campagnes : $error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
