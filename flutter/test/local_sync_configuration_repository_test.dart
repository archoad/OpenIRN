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

    test(
      'preserves one secure device token per tenant across switches and restarts',
      () async {
        const repository = LocalSyncConfigurationRepository();
        final initial = await repository.loadConfiguration();
        final tenantA = await repository.saveConfiguration(
          SyncConfiguration.empty(deviceId: initial.deviceId).copyWith(
            enabled: true,
            tenantId: 'tenant-a',
            apiToken: 'odt_tenant-a-secret',
          ),
        );

        await repository.clearTenantSelection();
        final tenantB = await repository.saveConfiguration(
          tenantA.copyWith(
            enabled: true,
            tenantId: 'tenant-b',
            apiToken: 'odt_tenant-b-secret',
          ),
        );
        expect(tenantB.apiToken, 'odt_tenant-b-secret');

        final switchedBack = await repository.saveConfiguration(
          tenantB.copyWith(tenantId: 'tenant-a', apiToken: ''),
        );
        expect(switchedBack.apiToken, 'odt_tenant-a-secret');

        AppSessionManager.instance.clearDeviceCredential();
        final reloaded = await repository.loadConfiguration();
        expect(reloaded.tenantId, 'tenant-a');
        expect(reloaded.apiToken, 'odt_tenant-a-secret');

        final switchedAgain = await repository.saveConfiguration(
          reloaded.copyWith(tenantId: 'tenant-b', apiToken: ''),
        );
        expect(switchedAgain.apiToken, 'odt_tenant-b-secret');
      },
    );

    test('revokes only the selected tenant credential locally', () async {
      const repository = LocalSyncConfigurationRepository();
      final initial = await repository.loadConfiguration();
      final tenantA = await repository.saveConfiguration(
        SyncConfiguration.empty(deviceId: initial.deviceId).copyWith(
          enabled: true,
          tenantId: 'tenant-a',
          apiToken: 'odt_tenant-a-secret',
        ),
      );
      final tenantB = await repository.saveConfiguration(
        tenantA.copyWith(tenantId: 'tenant-b', apiToken: 'odt_tenant-b-secret'),
      );

      await repository.clearDeviceAuthorization();
      final tenantBReloaded = await repository.loadConfiguration();
      expect(tenantBReloaded.apiToken, isEmpty);

      final tenantAReloaded = await repository.saveConfiguration(
        tenantB.copyWith(tenantId: 'tenant-a', apiToken: ''),
      );
      expect(tenantAReloaded.apiToken, 'odt_tenant-a-secret');
    });

    test('migrates the legacy single credential without losing pairing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'openirn.sync.configuration':
            '{"schemaVersion":6,"configuration":{"apiBaseUrl":"https://www.archoad.io/api","tenantId":"tenant-a","deviceId":"device-a","enabled":true,"apiToken":"","updatedAt":"2026-08-25T00:00:00.000Z"}}',
        'openirn.sync.deviceId': 'device-a',
      });
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'openirn.secure.deviceCredential.v1':
            '{"tenantId":"tenant-a","deviceId":"device-a","apiToken":"odt_legacy-secret"}',
      });
      const repository = LocalSyncConfigurationRepository();

      final reloaded = await repository.loadConfiguration();

      expect(reloaded.apiToken, 'odt_legacy-secret');
      const secureStorage = FlutterSecureStorage();
      expect(
        await secureStorage.read(key: 'openirn.secure.deviceCredential.v1'),
        isNull,
      );
      expect(
        await secureStorage.read(key: 'openirn.secure.deviceCredentials.v2'),
        contains('odt_legacy-secret'),
      );
    });
  });
}
