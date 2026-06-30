import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalUserRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('does not create a local default administrator anymore', () async {
      const repository = LocalUserRepository();

      final users = await repository.ensureDefaultUsers();

      expect(users, isEmpty);
    });

    test('purges legacy local user cache instead of saving it', () async {
      const repository = LocalUserRepository();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('openirn.localUsers', '{"users":[]}');

      await repository.saveUsers(const []);

      expect(preferences.containsKey('openirn.localUsers'), isFalse);
    });
  });
}
