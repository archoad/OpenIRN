import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/l10n/openirn_localizations.dart';
import 'package:openirn/presentation/assessment/assessment_summary_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await OpenIrnLocalizations.instance.initialize();
  });

  for (final language in [OpenIrnLanguage.es, OpenIrnLanguage.de]) {
    testWidgets(
      'assessment summary fits a portrait phone in ${language.code}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await OpenIrnLocalizations.instance.setLanguage(
          language,
          persist: false,
        );

        final timestamp = DateTime.utc(2026, 8, 26, 10);
        final campaign = LocalCampaign(
          id: 'campaign-test',
          referentialId: 'adri-irn-test',
          name: 'Campaña / Kampagne mit einem sehr langen Namen',
          description:
              'Descripción detallada / ausführliche Beschreibung der Kampagne.',
          createdAt: timestamp,
          updatedAt: timestamp,
          statusUpdatedAt: timestamp,
        );

        await tester.pumpWidget(
          OpenIrnLocalizationScope(
            controller: OpenIrnLocalizations.instance,
            child: MaterialApp(
              locale: Locale(language.code),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.2)),
                child: child!,
              ),
              home: AssessmentSummaryScreen(
                referential: _referential,
                campaign: campaign,
                criterionAnswers: const {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(
            OpenIrnLocalizations.instance.tr(
              'screen.summary.action.export_pdf',
            ),
          ),
          findsOneWidget,
        );

        final list = find.byType(ListView);
        for (var index = 0; index < 5; index += 1) {
          await tester.fling(list, const Offset(0, -700), 3000);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
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
    license: '',
  ),
  pillars: [],
  criteria: [],
);
