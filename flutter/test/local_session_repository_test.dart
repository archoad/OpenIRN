import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_session_repository.dart';
import 'package:openirn/data/repositories/local_user_repository.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSessionRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('uses the default administrator as first active user', () async {
      const repository = LocalSessionRepository();

      final activeUser = await repository.getActiveUser();

      expect(activeUser.id, AppUser.defaultAdministratorId);
      expect(activeUser.role, AppUserRole.administrator);
    });

    test('stores and reloads the selected active user', () async {
      const userRepository = LocalUserRepository();
      final evaluator = await userRepository.createUser(
        firstName: 'Alice',
        lastName: 'Martin',
        email: 'alice.martin@example.test',
        role: AppUserRole.evaluator,
      );
      const sessionRepository = LocalSessionRepository();

      final selected = await sessionRepository.setActiveUser(evaluator.id);
      final reloaded = await sessionRepository.getActiveUser();

      expect(selected.id, evaluator.id);
      expect(reloaded.id, evaluator.id);
      expect(reloaded.role, AppUserRole.evaluator);
    });
  });
}
