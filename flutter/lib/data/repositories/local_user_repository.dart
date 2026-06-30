import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_user.dart';
import '../api/openirn_api_client.dart';
import 'local_sync_configuration_repository.dart';

class LocalUserRepository {
  const LocalUserRepository({
    this.syncConfigurationRepository = const LocalSyncConfigurationRepository(),
    this.apiClient = const OpenIrnApiClient(),
  });

  static const _legacyStorageKey = 'openirn.localUsers';

  final LocalSyncConfigurationRepository syncConfigurationRepository;
  final OpenIrnApiClient apiClient;

  Future<List<AppUser>> loadUsers() async {
    await _purgeLegacyLocalUsers();

    final configuration = await syncConfigurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return const <AppUser>[];
    }

    final result = await apiClient.loadUsers(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    if (result.isAvailable || result.status == OpenIrnApiUsersStatus.empty) {
      return _sortUsers(result.users);
    }

    throw LocalUserRepositoryException('${result.title} — ${result.message}');
  }

  Future<List<AppUser>> ensureDefaultUsers() async {
    return loadUsers();
  }

  Future<AppUser> createUser({
    required String firstName,
    required String lastName,
    required String email,
    required AppUserRole role,
  }) async {
    final users = await loadUsers();
    final normalizedEmail = email.trim().toLowerCase();
    final existing = users.where((user) => user.email == normalizedEmail);
    if (existing.isNotEmpty) {
      throw const LocalUserRepositoryException(
        'Un utilisateur avec cet email existe déjà côté serveur.',
      );
    }

    final user = AppUser.create(
      firstName: firstName,
      lastName: lastName,
      email: normalizedEmail,
      role: role,
    );
    await _replaceUsers(<AppUser>[...users, user]);
    return user;
  }

  Future<AppUser?> updateUser(AppUser updatedUser) async {
    final users = await loadUsers();
    final now = DateTime.now().toUtc();
    AppUser? savedUser;
    final updated = <AppUser>[];

    for (final user in users) {
      if (user.id == updatedUser.id) {
        savedUser = updatedUser.copyWith(updatedAt: now);
        updated.add(savedUser);
      } else {
        updated.add(user);
      }
    }

    if (savedUser == null) {
      return null;
    }
    await _replaceUsers(updated);
    return savedUser;
  }

  Future<void> deleteUser({required String userId}) async {
    final users = await loadUsers();
    final updated = users
        .where((user) => user.id != userId)
        .toList(growable: false);
    if (updated.length == users.length) {
      throw const LocalUserRepositoryException(
        'Utilisateur introuvable côté serveur.',
      );
    }
    await _replaceUsers(updated);
  }

  Future<void> saveUsers(List<AppUser> users) async {
    // OpenIRN est désormais server-only pour les utilisateurs : cette méthode
    // est conservée uniquement pour compatibilité avec les anciens écrans qui
    // réalignaient un cache local après lecture API. Elle ne persiste plus rien.
    await _purgeLegacyLocalUsers();
  }

  Future<void> _replaceUsers(List<AppUser> users) async {
    final configuration = await syncConfigurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      throw const LocalUserRepositoryException(
        'Synchronisation impossible : terminal non autorisé.',
      );
    }

    final result = await apiClient.replaceUsers(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      users: _sortUsers(users),
    );

    if (!result.isAvailable && result.status != OpenIrnApiUsersStatus.empty) {
      throw LocalUserRepositoryException('${result.title} — ${result.message}');
    }
  }

  List<AppUser> _sortUsers(List<AppUser> users) {
    final sorted = users.toList();
    sorted.sort((a, b) {
      final activeWeightA = a.active ? 0 : 1;
      final activeWeightB = b.active ? 0 : 1;
      if (activeWeightA != activeWeightB) {
        return activeWeightA.compareTo(activeWeightB);
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return sorted;
  }

  Future<void> _purgeLegacyLocalUsers() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyStorageKey);
  }
}

class LocalUserRepositoryException implements Exception {
  final String message;

  const LocalUserRepositoryException(this.message);

  @override
  String toString() => message;
}
