import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openirn/data/repositories/local_sync_configuration_repository.dart';
import 'package:openirn/domain/models/sync_configuration.dart';
import 'package:openirn/domain/services/app_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSyncConfigurationRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      AppSessionManager.instance.clearDeviceCredential();
      AppSessionManager.instance.updateDeviceContext(
        tenantId: '',
        deviceId: '',
      );
    });

    test(
      'creates a local device id and fixed API URL without selecting a tenant when configuration is empty',
      () async {
        const repository = LocalSyncConfigurationRepository();

        final configuration = await repository.loadConfiguration();

        expect(configuration.deviceId, startsWith('openirn-'));
        expect(configuration.apiBaseUrl, SyncConfiguration.fixedApiBaseUrl);
        expect(configuration.tenantId, isEmpty);
        expect(configuration.apiToken, isEmpty);
        expect(configuration.enabled, isFalse);
        expect(configuration.isConfigured, isFalse);
      },
    );

    test(
      'stores the device token securely and never in public preferences',
      () async {
        const repository = LocalSyncConfigurationRepository();
        final initial = await repository.loadConfiguration();

        final saved = await repository.saveConfiguration(
          SyncConfiguration.empty(deviceId: initial.deviceId).copyWith(
            enabled: true,
            apiBaseUrl: 'https://openirn.example.org/api/',
            tenantId: 'archoad-lab',
            apiToken: 'odt_test-token-with-more-than-16-chars',
          ),
        );

        expect(saved.apiBaseUrl, SyncConfiguration.fixedApiBaseUrl);
        expect(saved.tenantId, 'archoad-lab');
        expect(saved.deviceId, initial.deviceId);
        expect(saved.apiToken, 'odt_test-token-with-more-than-16-chars');
        expect(saved.isConfigured, isTrue);

        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString('openirn.sync.configuration'),
          isNot(contains('odt_test-token-with-more-than-16-chars')),
        );

        AppSessionManager.instance.clearDeviceCredential();
        final reloaded = await repository.loadConfiguration();

        expect(reloaded.apiBaseUrl, SyncConfiguration.fixedApiBaseUrl);
        expect(reloaded.tenantId, 'archoad-lab');
        expect(reloaded.deviceId, initial.deviceId);
        expect(reloaded.apiToken, 'odt_test-token-with-more-than-16-chars');
        expect(reloaded.isConfigured, isTrue);
      },
    );

    test('never persists a user session token', () async {
      const repository = LocalSyncConfigurationRepository();
      final initial = await repository.loadConfiguration();
      final enrolled = await repository.saveConfiguration(
        SyncConfiguration.empty(deviceId: initial.deviceId).copyWith(
          enabled: true,
          tenantId: 'archoad-lab',
          apiToken: 'odt_device-secret',
        ),
      );

      AppSessionManager.instance.startSession(
        apiToken: 'ost_user-session',
        tenantId: enrolled.tenantId,
        deviceId: enrolled.deviceId,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      await repository.saveConfiguration(
        enrolled.copyWith(apiToken: 'ost_user-session'),
      );

      AppSessionManager.instance.clearDeviceCredential();
      final reloaded = await repository.loadConfiguration();

      expect(reloaded.apiToken, 'odt_device-secret');
      expect(reloaded.usesDeviceToken, isTrue);
      expect(AppSessionManager.instance.hasActiveSession, isFalse);
    });
  });
}
