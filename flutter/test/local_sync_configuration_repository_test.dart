import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_sync_configuration_repository.dart';
import 'package:openirn/domain/models/sync_configuration.dart';
import 'package:openirn/domain/services/app_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSyncConfigurationRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      AppSessionManager.instance.clearSession();
      AppSessionManager.instance.updateDeviceContext(
        tenantId: '',
        deviceId: '',
      );
    });

    test(
      'creates a local device id and fixed API URL when configuration is empty',
      () async {
        const repository = LocalSyncConfigurationRepository();

        final configuration = await repository.loadConfiguration();

        expect(configuration.deviceId, startsWith('openirn-'));
        expect(configuration.apiBaseUrl, SyncConfiguration.fixedApiBaseUrl);
        expect(configuration.tenantId, SyncConfiguration.defaultTenantId);
        expect(configuration.apiToken, isEmpty);
        expect(configuration.enabled, isFalse);
        expect(configuration.isConfigured, isFalse);
      },
    );

    test(
      'saves and reloads synchronization configuration without persisting API token',
      () async {
        const repository = LocalSyncConfigurationRepository();
        final initial = await repository.loadConfiguration();

        final saved = await repository.saveConfiguration(
          SyncConfiguration.empty(deviceId: initial.deviceId).copyWith(
            enabled: true,
            apiBaseUrl: 'https://openirn.example.org/api/',
            tenantId: 'archoad-lab',
            apiToken: 'test-token-with-more-than-16-chars',
          ),
        );

        expect(saved.apiBaseUrl, SyncConfiguration.fixedApiBaseUrl);
        expect(saved.tenantId, 'archoad-lab');
        expect(saved.deviceId, initial.deviceId);
        expect(saved.apiToken, 'test-token-with-more-than-16-chars');
        expect(saved.isConfigured, isTrue);

        AppSessionManager.instance.clearSession();
        final reloaded = await repository.loadConfiguration();

        expect(reloaded.apiBaseUrl, SyncConfiguration.fixedApiBaseUrl);
        expect(reloaded.tenantId, 'archoad-lab');
        expect(reloaded.deviceId, initial.deviceId);
        expect(reloaded.apiToken, isEmpty);
        expect(reloaded.isConfigured, isTrue);
      },
    );
  });
}
