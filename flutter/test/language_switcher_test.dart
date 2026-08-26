import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/l10n/openirn_localizations.dart';
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

  testWidgets('shows one current flag and switches among all languages', (
    tester,
  ) async {
    final i18n = OpenIrnLocalizations.instance;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => OpenIrnLocalizationScope(
          controller: i18n,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          appBar: AppBar(actions: const [OpenIrnLanguageSwitcher()]),
        ),
      ),
    );

    expect(find.text(OpenIrnLanguage.fr.flag), findsOneWidget);
    for (final language in OpenIrnLanguage.values.where(
      (language) => language != OpenIrnLanguage.fr,
    )) {
      expect(find.text(language.flag), findsNothing);
    }
    expect(
      find.descendant(
        of: find.byType(OpenIrnLanguageSwitcher),
        matching: find.byType(AnimatedContainer),
      ),
      findsNothing,
    );

    await tester.tap(find.text(OpenIrnLanguage.fr.flag));
    await tester.pumpAndSettle();

    for (final language in OpenIrnLanguage.values) {
      expect(
        find.text(language.flag),
        language == OpenIrnLanguage.fr ? findsNWidgets(2) : findsOneWidget,
      );
      expect(find.text(language.label), findsOneWidget);
    }

    await tester.tap(find.text(OpenIrnLanguage.es.flag));
    await tester.pumpAndSettle();

    expect(i18n.language, OpenIrnLanguage.es);
    expect(find.byType(OpenIrnLanguageSwitcher), findsOneWidget);
    expect(find.text(OpenIrnLanguage.es.flag), findsOneWidget);
    expect(find.text(OpenIrnLanguage.fr.flag), findsNothing);

    await tester.tap(find.text(OpenIrnLanguage.es.flag));
    await tester.pumpAndSettle();
    await tester.tap(find.text(OpenIrnLanguage.de.flag));
    await tester.pumpAndSettle();

    expect(i18n.language, OpenIrnLanguage.de);
    expect(find.text(OpenIrnLanguage.de.flag), findsOneWidget);
    expect(find.text(OpenIrnLanguage.es.flag), findsNothing);
  });
}
