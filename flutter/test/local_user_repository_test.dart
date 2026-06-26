import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_user_repository.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalUserRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('creates a default administrator', () async {
      const repository = LocalUserRepository();

      final users = await repository.ensureDefaultUsers();

      expect(users, hasLength(1));
      expect(users.first.id, AppUser.defaultAdministratorId);
      expect(users.first.role, AppUserRole.administrator);
    });

    test('creates and reloads a local user', () async {
      const repository = LocalUserRepository();

      final user = await repository.createUser(
        firstName: 'Alice',
        lastName: 'Martin',
        email: 'Alice.Martin@example.test',
        role: AppUserRole.evaluator,
      );

      final users = await repository.loadUsers();

      expect(users.any((candidate) => candidate.id == user.id), isTrue);
      expect(user.email, 'alice.martin@example.test');
      expect(user.role, AppUserRole.evaluator);
    });
  });
}
