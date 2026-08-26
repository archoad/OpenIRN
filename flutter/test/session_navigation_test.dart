import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/services/app_session_manager.dart';
import 'package:openirn/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppSessionManager.instance.clearSession();
  });

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
