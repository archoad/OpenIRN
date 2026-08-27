import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/l10n/openirn_localizations.dart';
import 'package:openirn/presentation/about/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'OpenIRN',
      packageName: 'openirn',
      version: '1.4.1',
      buildNumber: '20',
      buildSignature: '',
    );
    await OpenIrnLocalizations.instance.initialize();
    await OpenIrnLocalizations.instance.setLanguage(
      OpenIrnLanguage.fr,
      persist: false,
    );
  });

  testWidgets('the About screen displays the complete GPLv3 license', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenIrnLocalizationScope(
        controller: OpenIrnLocalizations.instance,
        child: const MaterialApp(home: AboutScreen(referential: _referential)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Code applicatif sous GNU GPL v3 ou ultérieure'),
      findsOneWidget,
    );

    await tester.tap(find.text('Lire la licence complète'));
    await tester.pumpAndSettle();

    expect(find.text('Licence GNU GPL d’OpenIRN'), findsOneWidget);
    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);
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
