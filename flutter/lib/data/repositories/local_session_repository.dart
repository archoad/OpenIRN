import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_user.dart';
import 'local_user_repository.dart';

class LocalSessionRepository {
  const LocalSessionRepository({
    this.userRepository = const LocalUserRepository(),
  });

  static const _activeUserIdKey = 'openirn.localSession.activeUserId';

  final LocalUserRepository userRepository;

  Future<AppUser> getActiveUser() async {
    final users = await userRepository.ensureDefaultUsers();
    final preferences = await SharedPreferences.getInstance();
    final storedUserId = preferences.getString(_activeUserIdKey)?.trim();

    for (final user in users) {
      if (user.id == storedUserId && user.active) {
        return user;
      }
    }

    final fallback = _fallbackUser(users);
    await preferences.setString(_activeUserIdKey, fallback.id);
    return fallback;
  }

  Future<AppUser> setActiveUser(String userId) async {
    final users = await userRepository.ensureDefaultUsers();
    for (final user in users) {
      if (user.id == userId && user.active) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_activeUserIdKey, user.id);
        return user;
      }
    }
    throw const LocalSessionRepositoryException(
      'Utilisateur actif introuvable ou inactif.',
    );
  }

  Future<void> clearActiveUser() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_activeUserIdKey);
  }

  AppUser _fallbackUser(List<AppUser> users) {
    for (final user in users) {
      if (user.id == AppUser.defaultAdministratorId && user.active) {
        return user;
      }
    }
    for (final user in users) {
      if (user.active) {
        return user;
      }
    }
    return AppUser.defaultAdministrator();
  }
}

class LocalSessionRepositoryException implements Exception {
  final String message;

  const LocalSessionRepositoryException(this.message);

  @override
  String toString() => message;
}
