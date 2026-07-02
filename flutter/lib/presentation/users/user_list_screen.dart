import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _syncConfigurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  final _appSyncCoordinator = AppSyncCoordinator.instance;
  late Future<_UserListStateData> _usersFuture;
  int _lastAppliedSyncSerial = 0;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
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

  Future<_UserListStateData> _loadUsers() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();

    if (!configuration.isConfigured) {
      return const _UserListStateData(
        users: <AppUser>[],
        serverAvailable: false,
        sourceLabel: 'Terminal non autorisé',
        sourceMessage:
            'Veuillez autoriser ce terminal avant d’accéder à la liste des utilisateurs.',
      );
    }

    final centralUsers = await _apiClient.loadUsers(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    if (centralUsers.isAvailable ||
        centralUsers.status == OpenIrnApiUsersStatus.empty) {
      return _UserListStateData(
        users: centralUsers.users,
        serverAvailable: true,
        sourceLabel: 'Base centrale serveur',
        sourceMessage: centralUsers.message,
        apiBaseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );
    }

    return _UserListStateData(
      users: const <AppUser>[],
      serverAvailable: false,
      sourceLabel: 'Serveur indisponible',
      sourceMessage:
          '${centralUsers.title} — ${centralUsers.message}. Les utilisateurs ne sont plus mis en cache localement.',
      apiBaseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _usersFuture = _loadUsers();
    });
    await _usersFuture;
  }

  Future<_UserListStateData> _loadWritableCentralUsers() async {
    final configuration = await _syncConfigurationRepository
        .loadConfiguration();
    if (!configuration.isConfigured) {
      throw const _UserSyncException(
        'Synchronisation impossible : la configuration serveur est incomplète.',
      );
    }

    final centralUsers = await _apiClient.loadUsers(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    if (!centralUsers.isAvailable &&
        centralUsers.status != OpenIrnApiUsersStatus.empty) {
      throw _UserSyncException(
        '${centralUsers.title} — ${centralUsers.message}',
      );
    }

    return _UserListStateData(
      users: centralUsers.users,
      serverAvailable: true,
      sourceLabel: 'Base centrale serveur',
      sourceMessage: centralUsers.message,
      apiBaseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
  }

  Future<void> _replaceCentralUsers(
    List<AppUser> users, {
    required String successMessage,
  }) async {
    setState(() {
      _working = true;
    });

    try {
      final configuration = await _syncConfigurationRepository
          .loadConfiguration();
      if (!configuration.isConfigured) {
        throw const _UserSyncException(
          'Synchronisation impossible : la configuration serveur est incomplète.',
        );
      }

      final result = await _apiClient.replaceUsers(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
        users: users,
      );

      if (!result.isAvailable && result.status != OpenIrnApiUsersStatus.empty) {
        throw _UserSyncException('${result.title} — ${result.message}');
      }

      await _refresh();
      await _appSyncCoordinator.pushNow();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _createUser() async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (_) => const _UserDialog(),
    );
    if (result == null) {
      return;
    }

    try {
      final state = await _loadWritableCentralUsers();
      final normalizedEmail = result.email.trim().toLowerCase();
      final duplicate = state.users.any(
        (user) => user.email == normalizedEmail,
      );
      if (duplicate) {
        throw const _UserSyncException(
          'Un utilisateur avec cet email existe déjà dans la base centrale.',
        );
      }

      final user = AppUser.create(
        firstName: result.firstName,
        lastName: result.lastName,
        email: normalizedEmail,
        role: result.role,
      );

      await _replaceCentralUsers(
        <AppUser>[...state.users, user],
        successMessage:
            'Utilisateur créé et synchronisé immédiatement avec le serveur.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Création impossible : $error')));
    }
  }

  Future<void> _editUser(AppUser user) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (_) => _UserDialog(user: user),
    );
    if (result == null) {
      return;
    }

    try {
      final state = await _loadWritableCentralUsers();
      final normalizedEmail = result.email.trim().toLowerCase();
      final duplicate = state.users.any(
        (candidate) =>
            candidate.id != user.id && candidate.email == normalizedEmail,
      );
      if (duplicate) {
        throw const _UserSyncException(
          'Un autre utilisateur utilise déjà cet email dans la base centrale.',
        );
      }

      var updatedExistingUser = false;
      final updatedUsers = state.users
          .map((candidate) {
            if (candidate.id != user.id) {
              return candidate;
            }
            updatedExistingUser = true;
            return candidate.copyWith(
              firstName: result.firstName,
              lastName: result.lastName,
              email: normalizedEmail,
              role: result.role,
              updatedAt: DateTime.now().toUtc(),
            );
          })
          .toList(growable: false);

      if (!updatedExistingUser) {
        throw const _UserSyncException(
          'Utilisateur introuvable. Veuillez actualiser la page puis réessayer.',
        );
      }

      await _replaceCentralUsers(
        updatedUsers,
        successMessage:
            'Utilisateur modifié et synchronisé immédiatement avec le serveur.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : $error')),
      );
    }
  }

  Future<void> _changeUserPin(AppUser user, _UserListStateData state) async {
    if (!state.serverAvailable ||
        state.apiToken.trim().isEmpty ||
        state.tenantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Modification impossible : la liste des utilisateurs est indisponible ou la synchronisation serveur n’est pas configurée.',
          ),
        ),
      );
      return;
    }

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserPinDialog(user: user),
    );
    if (pin == null) {
      return;
    }

    final result = await _apiClient.updateUserPin(
      baseUrl: state.apiBaseUrl,
      tenantId: state.tenantId,
      apiToken: state.apiToken,
      userId: user.id,
      pin: pin,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.title} — ${result.message}')),
    );
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Supprimer l’utilisateur ?'),
        content: ResponsiveDialogContent(
          maxWidth: 560,
          child: Text(
            'L’utilisateur « ${user.displayName} » sera supprimé de la base centrale serveur.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      final state = await _loadWritableCentralUsers();
      final updatedUsers = state.users
          .where((candidate) => candidate.id != user.id)
          .toList(growable: false);
      if (updatedUsers.length == state.users.length) {
        throw const _UserSyncException(
          'Utilisateur introuvable. Veuillez actualiser la page puis réessayer.',
        );
      }

      await _replaceCentralUsers(
        updatedUsers,
        successMessage:
            'Utilisateur supprimé et synchronisé immédiatement avec le serveur.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Utilisateurs',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh_users',
            label: 'Actualiser',
            icon: Icons.refresh_outlined,
            enabled: !_working,
            onSelected: _refresh,
          ),
          OpenIrnAppBarAction(
            id: 'new_user',
            label: 'Nouvel utilisateur',
            icon: Icons.person_add_alt_1_outlined,
            enabled: !_working,
            onSelected: _createUser,
          ),
        ],
      ),
      body: FutureBuilder<_UserListStateData>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Chargement impossible : ${snapshot.error}'),
            );
          }
          final state = snapshot.data;
          final users = state?.users ?? const <AppUser>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 950),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _IntroCard(state: state);
                  }
                  final user = users[index - 1];
                  final serverAvailable = state?.serverAvailable ?? false;
                  return _UserCard(
                    user: user,
                    centralPinsAvailable: serverAvailable,
                    onEdit: serverAvailable && !_working
                        ? () => _editUser(user)
                        : null,
                    onChangePin: state == null || !serverAvailable || _working
                        ? null
                        : () => _changeUserPin(user, state),
                    onDelete: !serverAvailable || _working
                        ? null
                        : () => _deleteUser(user),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UserListStateData {
  final List<AppUser> users;
  final bool serverAvailable;
  final String sourceLabel;
  final String sourceMessage;
  final String apiBaseUrl;
  final String tenantId;
  final String apiToken;

  const _UserListStateData({
    required this.users,
    required this.serverAvailable,
    required this.sourceLabel,
    required this.sourceMessage,
    this.apiBaseUrl = '',
    this.tenantId = '',
    this.apiToken = '',
  });
}

class _UserSyncException implements Exception {
  final String message;

  const _UserSyncException(this.message);

  @override
  String toString() => message;
}

class _IntroCard extends StatelessWidget {
  final _UserListStateData? state;

  const _IntroCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverAvailable = state?.serverAvailable ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Annuaire et codes utilisateurs',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Les administrateurs et pilotes IRN modifient ici la base utilisateurs centrale du serveur.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    serverAvailable
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 18,
                  ),
                  label: Text(state?.sourceLabel ?? 'Chargement'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state?.sourceMessage ?? 'Chargement de la base utilisateurs.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  final bool centralPinsAvailable;
  final VoidCallback? onEdit;
  final VoidCallback? onChangePin;
  final VoidCallback? onDelete;

  const _UserCard({
    required this.user,
    required this.centralPinsAvailable,
    required this.onEdit,
    required this.onChangePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final header = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.role.description,
                        style: theme.textTheme.bodySmall,
                        maxLines: compact ? 4 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            );

            final chips = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(user.role.label)),
                if (centralPinsAvailable)
                  const Chip(
                    avatar: Icon(Icons.key_outlined, size: 18),
                    label: Text('Code serveur'),
                  ),
              ],
            );

            final actions = Wrap(
              alignment: compact ? WrapAlignment.start : WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: centralPinsAvailable ? onChangePin : null,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Code'),
                ),
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 12),
                  chips,
                  const SizedBox(height: 8),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, const SizedBox(height: 12), chips],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: actions,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UserFormResult {
  final String firstName;
  final String lastName;
  final String email;
  final AppUserRole role;
  const _UserFormResult({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
  });
}

class _UserDialog extends StatefulWidget {
  final AppUser? user;

  const _UserDialog({this.user});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late AppUserRole _role;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _role = user?.role ?? AppUserRole.evaluator;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(
      _UserFormResult(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        role: _role,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = isResponsiveDialogCompact(context, maxWidth: 820);

    Widget buildFirstNameField() {
      return TextFormField(
        controller: _firstNameController,
        autofocus: shouldAutofocusTextField(context),
        decoration: const InputDecoration(
          labelText: 'Prénom',
          border: OutlineInputBorder(),
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Prénom obligatoire.'
            : null,
      );
    }

    Widget buildLastNameField() {
      return TextFormField(
        controller: _lastNameController,
        decoration: const InputDecoration(
          labelText: 'Nom',
          border: OutlineInputBorder(),
        ),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Nom obligatoire.' : null,
      );
    }

    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: Text(
        widget.user == null ? 'Nouvel utilisateur' : 'Modifier l’utilisateur',
      ),
      content: ResponsiveDialogContent(
        maxWidth: 820,
        minWidth: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (compact) ...[
                  buildFirstNameField(),
                  const SizedBox(height: 10),
                  buildLastNameField(),
                ] else ...[
                  Row(
                    children: [
                      Expanded(child: buildFirstNameField()),
                      const SizedBox(width: 10),
                      Expanded(child: buildLastNameField()),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  keyboardType: safeKeyboardType(
                    context,
                    TextInputType.emailAddress,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Email obligatoire.';
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Email invalide.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<AppUserRole>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Rôle',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final role in AppUserRole.values)
                      DropdownMenuItem<AppUserRole>(
                        value: role,
                        child: Text(
                          role.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (role) => setState(() => _role = role ?? _role),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _UserPinDialog extends StatefulWidget {
  final AppUser user;

  const _UserPinDialog({required this.user});

  @override
  State<_UserPinDialog> createState() => _UserPinDialogState();
}

class _UserPinDialogState extends State<_UserPinDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePin = true;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(_pinController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.displayName.isNotEmpty
        ? widget.user.displayName
        : widget.user.email;
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Modifier le code utilisateur'),
      content: ResponsiveDialogContent(
        maxWidth: 560,
        child: Form(
          key: _formKey,
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
                const SizedBox(height: 4),
                Text(widget.user.role.label),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pinController,
                  autofocus: shouldAutofocusTextField(context),
                  obscureText: _obscurePin,
                  keyboardType: safeKeyboardType(
                    context,
                    TextInputType.visiblePassword,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: 'Nouveau code',
                    border: const OutlineInputBorder(),
                    helperText: 'Entre 4 et 32 caractères.',
                    suffixIcon: IconButton(
                      tooltip: _obscurePin ? 'Afficher' : 'Masquer',
                      onPressed: () =>
                          setState(() => _obscurePin = !_obscurePin),
                      icon: Icon(
                        _obscurePin
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final pin = value?.trim() ?? '';
                    if (pin.length < 4) {
                      return 'Code trop court.';
                    }
                    if (pin.length > 32) {
                      return 'Code trop long.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscurePin,
                  keyboardType: safeKeyboardType(
                    context,
                    TextInputType.visiblePassword,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le code',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if ((value?.trim() ?? '') != _pinController.text.trim()) {
                      return 'Les codes ne correspondent pas.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.key_outlined),
          label: const Text('Mettre à jour'),
        ),
      ],
    );
  }
}
