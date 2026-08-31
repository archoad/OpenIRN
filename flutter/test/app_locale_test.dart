import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/l10n/openirn_localizations.dart';
import 'package:openirn/main.dart';
import 'package:openirn/presentation/common/openirn_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await OpenIrnLocalizations.instance.initialize();
    await OpenIrnLocalizations.instance.setLanguage(
      OpenIrnLanguage.fr,
      persist: false,
    );
  });

  tearDown(() async {
    await OpenIrnLocalizations.instance.setLanguage(
      OpenIrnLanguage.fr,
      persist: false,
    );
  });

  testWidgets('synchronizes Flutter locale with the selected language', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenIrnApp(
        home: Scaffold(
          appBar: AppBar(actions: const [OpenIrnLanguageSwitcher()]),
          body: const _LocaleProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.supportedLocales.map((locale) => locale.languageCode), [
      'fr',
      'en',
      'es',
      'de',
    ]);
    expect(
      materialApp.localizationsDelegates,
      containsAll([
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ]),
    );
    expect(find.text('locale:fr'), findsOneWidget);
    expect(find.text('back:Retour'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('openirn-language-flag-current-fr')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('openirn-language-flag-menu-es')),
    );
    await tester.pumpAndSettle();

    expect(find.text('locale:es'), findsOneWidget);
    expect(find.text('back:Atrás'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('es'),
    );

    unawaited(OpenIrnLocalizations.instance.setLanguage(OpenIrnLanguage.de));
    await tester.pumpAndSettle();

    expect(find.text('locale:de'), findsOneWidget);
    expect(find.text('back:Zurück'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('de'),
    );
  });
}

class _LocaleProbe extends StatelessWidget {
  const _LocaleProbe();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('locale:${Localizations.localeOf(context).languageCode}'),
        Text('back:${MaterialLocalizations.of(context).backButtonTooltip}'),
      ],
    );
  }
}
