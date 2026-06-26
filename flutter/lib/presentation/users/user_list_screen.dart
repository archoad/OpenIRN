import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_session_repository.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../domain/models/app_user.dart';
import '../common/openirn_app_bar.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _repository = const LocalUserRepository();
  final _sessionRepository = const LocalSessionRepository();
  final _syncConfigurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient();
  late Future<_UserListStateData> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
  }

  Future<_UserListStateData> _loadUsers() async {
    final localUsers = await _repository.ensureDefaultUsers();
    final activeUser = await _sessionRepository.getActiveUser();
    final configuration = await _syncConfigurationRepository.loadConfiguration();

    if (configuration.isConfigured) {
      final centralUsers = await _apiClient.loadUsers(
        baseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );

      if (centralUsers.hasUsers) {
        await _repository.saveUsers(centralUsers.users);
        return _UserListStateData(
          users: centralUsers.users,
          activeUser: activeUser,
          serverAvailable: true,
          sourceLabel: 'Base centrale serveur',
          sourceMessage: centralUsers.message,
          apiBaseUrl: configuration.apiBaseUrl,
          tenantId: configuration.tenantId,
          apiToken: configuration.apiToken,
        );
      }

      return _UserListStateData(
        users: localUsers,
        activeUser: activeUser,
        serverAvailable: false,
        sourceLabel: 'Secours hors ligne',
        sourceMessage: '${centralUsers.title} — ${centralUsers.message}',
        apiBaseUrl: configuration.apiBaseUrl,
        tenantId: configuration.tenantId,
        apiToken: configuration.apiToken,
      );
    }

    return _UserListStateData(
      users: localUsers,
      activeUser: activeUser,
      serverAvailable: false,
      sourceLabel: 'Mode hors ligne',
      sourceMessage: 'La synchronisation API n’est pas configurée. Les codes centraux ne peuvent pas être modifiés depuis ce terminal.',
    );
  }

  Future<void> _setActiveUser(AppUser user) async {
    try {
      await _sessionRepository.setActiveUser(user.id);
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session de ce terminal active : ${user.displayName}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Changement de session impossible : $error')),
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _usersFuture = _loadUsers();
    });
    await _usersFuture;
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
      await _repository.createUser(
        firstName: result.firstName,
        lastName: result.lastName,
        email: result.email,
        role: result.role,
      );
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur ajouté localement. Lance une synchronisation pour l’envoyer au serveur.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Création impossible : $error')),
      );
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

    await _repository.updateUser(
      user.copyWith(
        firstName: result.firstName,
        lastName: result.lastName,
        email: result.email,
        role: user.isDefaultAdministrator ? AppUserRole.administrator : result.role,
        active: result.active,
      ),
    );
    await _refresh();
  }

  Future<void> _changeUserPin(AppUser user, _UserListStateData state) async {
    if (!state.serverAvailable || state.apiToken.trim().isEmpty || state.tenantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modification impossible : base centrale indisponible ou synchronisation API non configurée.'),
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
        title: const Text('Supprimer l’utilisateur ?'),
        content: Text('L’utilisateur « ${user.displayName} » sera retiré de l’annuaire local. La base centrale sera réalignée au prochain push de l’administrateur.'),
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
      await _repository.deleteUser(userId: user.id);
      await _refresh();
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
            onSelected: _refresh,
          ),
          OpenIrnAppBarAction(
            id: 'new_user',
            label: 'Nouvel utilisateur',
            icon: Icons.person_add_alt_1_outlined,
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
            return Center(child: Text('Chargement impossible : ${snapshot.error}'));
          }
          final state = snapshot.data;
          final users = state?.users ?? const <AppUser>[];
          final activeUser = state?.activeUser;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 950),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _IntroCard(state: state);
                  }
                  final user = users[index - 1];
                  return _UserCard(
                    user: user,
                    activeUser: activeUser,
                    centralPinsAvailable: state?.serverAvailable ?? false,
                    onActivate: user.active ? () => _setActiveUser(user) : null,
                    onEdit: () => _editUser(user),
                    onChangePin: state == null ? null : () => _changeUserPin(user, state),
                    onDelete: user.isDefaultAdministrator ? null : () => _deleteUser(user),
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
  final AppUser? activeUser;
  final bool serverAvailable;
  final String sourceLabel;
  final String sourceMessage;
  final String apiBaseUrl;
  final String tenantId;
  final String apiToken;

  const _UserListStateData({
    required this.users,
    required this.activeUser,
    required this.serverAvailable,
    required this.sourceLabel,
    required this.sourceMessage,
    this.apiBaseUrl = '',
    this.tenantId = '',
    this.apiToken = '',
  });
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
            Text('Annuaire et codes utilisateurs', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Les administrateurs et pilotes IRN peuvent modifier ici les codes personnels utilisés à l’ouverture d’une campagne.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(serverAvailable ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18),
                  label: Text(state?.sourceLabel ?? 'Chargement'),
                ),
                Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(
                    'Session active : ${state?.activeUser?.displayName ?? 'non définie'}',
                    overflow: TextOverflow.ellipsis,
                  ),
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
  final AppUser? activeUser;
  final bool centralPinsAvailable;
  final VoidCallback? onActivate;
  final VoidCallback onEdit;
  final VoidCallback? onChangePin;
  final VoidCallback? onDelete;

  const _UserCard({
    required this.user,
    required this.activeUser,
    required this.centralPinsAvailable,
    required this.onActivate,
    required this.onEdit,
    required this.onChangePin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrentSession = activeUser?.id == user.id;
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
                CircleAvatar(
                  child: Icon(user.active ? Icons.person_outline : Icons.person_off_outlined),
                ),
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
                Chip(label: Text(user.active ? 'Actif' : 'Inactif')),
                if (centralPinsAvailable)
                  const Chip(
                    avatar: Icon(Icons.key_outlined, size: 18),
                    label: Text('Code central'),
                  ),
                if (isCurrentSession)
                  const Chip(
                    avatar: Icon(Icons.verified_user_outlined, size: 18),
                    label: Text('Session'),
                  ),
              ],
            );

            final actions = Wrap(
              alignment: compact ? WrapAlignment.start : WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                if (!isCurrentSession)
                  TextButton.icon(
                    onPressed: onActivate,
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Activer'),
                  ),
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
                    children: [
                      header,
                      const SizedBox(height: 12),
                      chips,
                    ],
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
  final bool active;

  const _UserFormResult({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.active,
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
  late bool _active;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _role = user?.role ?? AppUserRole.evaluator;
    _active = user?.active ?? true;
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
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDefaultAdmin = widget.user?.isDefaultAdministrator ?? false;
    final compact = MediaQuery.sizeOf(context).width < 560;

    Widget buildFirstNameField() {
      return TextFormField(
        controller: _firstNameController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Prénom',
          border: OutlineInputBorder(),
        ),
        validator: (value) => value == null || value.trim().isEmpty ? 'Prénom obligatoire.' : null,
      );
    }

    Widget buildLastNameField() {
      return TextFormField(
        controller: _lastNameController,
        decoration: const InputDecoration(
          labelText: 'Nom',
          border: OutlineInputBorder(),
        ),
        validator: (value) => value == null || value.trim().isEmpty ? 'Nom obligatoire.' : null,
      );
    }

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.user == null ? 'Nouvel utilisateur' : 'Modifier l’utilisateur'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
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
                  keyboardType: TextInputType.emailAddress,
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
                  onChanged: isDefaultAdmin ? null : (role) => setState(() => _role = role ?? _role),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Utilisateur actif'),
                  value: _active,
                  onChanged: isDefaultAdmin ? null : (value) => setState(() => _active = value),
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
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
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
    final displayName = widget.user.displayName.isNotEmpty ? widget.user.displayName : widget.user.email;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Modifier le code utilisateur'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
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
                autofocus: true,
                obscureText: _obscurePin,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'Nouveau code',
                  border: const OutlineInputBorder(),
                  helperText: 'Entre 4 et 32 caractères.',
                  suffixIcon: IconButton(
                    tooltip: _obscurePin ? 'Afficher' : 'Masquer',
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                    icon: Icon(_obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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
                keyboardType: TextInputType.visiblePassword,
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
