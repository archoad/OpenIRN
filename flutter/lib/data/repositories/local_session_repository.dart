import '../../domain/models/app_user.dart';
import '../../domain/services/app_session_manager.dart';
import 'local_user_repository.dart';

class LocalSessionRepository {
  const LocalSessionRepository({
    this.userRepository = const LocalUserRepository(),
  });

  final LocalUserRepository userRepository;

  Future<AppUser> getActiveUser() async {
    final activeUser = AppSessionManager.instance.activeUser;
    if (activeUser != null && activeUser.active) {
      return activeUser;
    }

    throw const LocalSessionRepositoryException(
      'Aucune session utilisateur active. Veuillez vous authentifier avec votre profil et votre code personnel.',
    );
  }

  Future<AppUser> setActiveUser(String userId) async {
    final users = await userRepository.loadUsers();
    for (final user in users) {
      if (user.id == userId && user.active) {
        AppSessionManager.instance.setActiveUser(user);
        return user;
      }
    }
    throw const LocalSessionRepositoryException(
      'Utilisateur actif introuvable côté serveur.',
    );
  }

  Future<void> clearActiveUser() async {
    AppSessionManager.instance.clearSession();
  }
}

class LocalSessionRepositoryException implements Exception {
  final String message;

  const LocalSessionRepositoryException(this.message);

  @override
  String toString() => message;
}
