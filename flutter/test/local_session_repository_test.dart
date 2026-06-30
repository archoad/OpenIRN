import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_session_repository.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:openirn/domain/services/app_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSessionRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      AppSessionManager.instance.clearSession();
    });

    test('fails when no server session is active', () async {
      const repository = LocalSessionRepository();

      expect(
        repository.getActiveUser(),
        throwsA(isA<LocalSessionRepositoryException>()),
      );
    });

    test('returns the authenticated in-memory server user', () async {
      final user = AppUser.create(
        firstName: 'Alice',
        lastName: 'Martin',
        email: 'alice.martin@example.test',
        role: AppUserRole.evaluator,
      );
      AppSessionManager.instance.startSession(
        apiToken: 'ost_test',
        tenantId: 'archoad',
        deviceId: 'device-test',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        activeUser: user,
      );

      const repository = LocalSessionRepository();
      final activeUser = await repository.getActiveUser();

      expect(activeUser.id, user.id);
      expect(activeUser.role, AppUserRole.evaluator);
    });
  });
}
