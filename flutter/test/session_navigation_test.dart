import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/api_irn_referential_repository.dart';
import 'package:openirn/data/repositories/local_sync_configuration_repository.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/sync_configuration.dart';
import 'package:openirn/domain/repositories/irn_referential_repository.dart';
import 'package:openirn/domain/services/app_session_manager.dart';
import 'package:openirn/main.dart';
import 'package:openirn/presentation/referential/referential_overview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppSessionManager.instance.clearDeviceCredential();
    AppSessionManager.instance.updateDeviceContext(tenantId: '', deviceId: '');
  });

  testWidgets(
    'a revoked device credential is discarded and enrollment is required',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      const configurationRepository = LocalSyncConfigurationRepository();
      final initial = await configurationRepository.loadConfiguration();
      await configurationRepository.saveConfiguration(
        SyncConfiguration.empty(deviceId: initial.deviceId).copyWith(
          enabled: true,
          tenantId: 'tenant-revoked',
          apiToken: 'odt_revoked-device-token',
        ),
      );

      await tester.pumpWidget(
        const OpenIrnApp(
          home: ReferentialOverviewScreen(
            repository: _RevokedDeviceReferentialRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Autoriser ce terminal'), findsOneWidget);
      expect(find.text('Déverrouiller OpenIRN'), findsNothing);
      final reloaded = await configurationRepository.loadConfiguration();
      expect(reloaded.hasSelectedTenant, isTrue);
      expect(reloaded.apiToken, isEmpty);
      expect(reloaded.isConfigured, isFalse);
    },
  );

  testWidgets(
    'a notification without an active session does not close the current route',
    (tester) async {
      AppSessionManager.instance.clearSession();
      await tester.pumpWidget(const OpenIrnApp(home: _NavigationTestHome()));

      await tester.tap(find.text('Open secondary route'));
      await tester.pumpAndSettle();
      expect(find.text('Secondary route'), findsOneWidget);

      AppSessionManager.instance.clearDeviceCredential();
      await tester.pumpAndSettle();

      expect(find.text('Secondary route'), findsOneWidget);
    },
  );

  testWidgets('ending an active session returns to the first route', (
    tester,
  ) async {
    AppSessionManager.instance.clearSession();
    await tester.pumpWidget(const OpenIrnApp(home: _NavigationTestHome()));

    await tester.tap(find.text('Open secondary route'));
    await tester.pumpAndSettle();
    expect(find.text('Secondary route'), findsOneWidget);

    AppSessionManager.instance.startSession(
      apiToken: 'ost_test-session',
      tenantId: 'tenant-test',
      deviceId: 'device-test',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(AppSessionManager.instance.hasActiveSession, isTrue);
    expect(openIrnNavigatorKey.currentState?.canPop(), isTrue);
    await tester.pump();
    AppSessionManager.instance.clearSession(reason: 'Session test terminée.');
    await tester.pumpAndSettle();

    expect(find.text('Secondary route'), findsNothing);
    expect(find.text('Open secondary route'), findsOneWidget);
  });
}

class _RevokedDeviceReferentialRepository implements IrnReferentialRepository {
  const _RevokedDeviceReferentialRepository();

  @override
  Future<IrnReferential> getActiveReferential() {
    throw const ApiIrnReferentialException(
      'Autorisation refusée',
      statusCode: 403,
    );
  }
}

class _NavigationTestHome extends StatelessWidget {
  const _NavigationTestHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('Secondary route')),
                ),
              ),
            );
          },
          child: const Text('Open secondary route'),
        ),
      ),
    );
  }
}
