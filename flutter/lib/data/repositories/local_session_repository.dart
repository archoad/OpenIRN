import '../../domain/models/app_user.dart';
import '../../domain/services/app_session_manager.dart';

class LocalSessionRepository {
  const LocalSessionRepository();

  Future<AppUser> getActiveUser() async {
    final activeUser = AppSessionManager.instance.activeUser;
    if (activeUser != null && activeUser.active) {
      return activeUser;
    }

    throw const LocalSessionRepositoryException(
      'Aucune session utilisateur active. Veuillez vous authentifier avec votre profil et votre code personnel.',
    );
  }
}

class LocalSessionRepositoryException implements Exception {
  final String message;

  const LocalSessionRepositoryException(this.message);

  @override
  String toString() => message;
}
