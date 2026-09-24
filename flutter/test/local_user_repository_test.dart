import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openirn/data/repositories/local_user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalUserRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    test(
      'purges legacy users without creating a local administrator',
      () async {
        const repository = LocalUserRepository();
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString('openirn.localUsers', '{"users":[]}');

        final users = await repository.ensureDefaultUsers();

        expect(users, isEmpty);
        expect(preferences.containsKey('openirn.localUsers'), isFalse);
      },
    );
  });
}
