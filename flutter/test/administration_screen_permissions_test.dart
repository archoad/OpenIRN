import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/presentation/admin/administration_screen.dart';

void main() {
  AppUser user(AppUserRole role) => AppUser(
    tenantId: 'tenant-a',
    id: role.jsonValue,
    firstName: role.label,
    lastName: 'Test',
    email: '${role.jsonValue}@example.test',
    role: role,
    active: true,
    createdAt: DateTime.utc(2026, 9, 16),
    updatedAt: DateTime.utc(2026, 9, 16),
  );

  Future<void> pumpAdministration(WidgetTester tester, AppUserRole role) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationScreen(
          referential: _referential,
          activeUser: user(role),
        ),
      ),
    );
  }

  testWidgets('campaign history is hidden from the IRN pilot', (tester) async {
    await pumpAdministration(tester, AppUserRole.campaignManager);

    expect(find.byIcon(Icons.manage_history_outlined), findsNothing);
  });

  testWidgets('campaign history remains visible to the administrator', (
    tester,
  ) async {
    await pumpAdministration(tester, AppUserRole.administrator);

    expect(find.byIcon(Icons.manage_history_outlined), findsOneWidget);
  });
}

const _referential = IrnReferential(
  id: 'adri-irn-test',
  version: 'vtest',
  source: IrnSource(
    type: 'test',
    url: '',
    projectPath: '',
    defaultBranch: 'main',
    filePath: '',
    license: 'CC BY-NC-ND 4.0',
  ),
  pillars: [],
  criteria: [],
);
