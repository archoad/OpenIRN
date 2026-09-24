import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/l10n/openirn_localizations.dart';
import 'package:openirn/presentation/assessment/assessment_screen.dart';
import 'package:openirn/presentation/common/irn_pillar_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await OpenIrnLocalizations.instance.initialize();
  });

  test('uses compact layout below the tablet breakpoint', () {
    expect(
      assessmentLayoutModeForWidth(AssessmentLayoutBreakpoints.medium - 1),
      AssessmentLayoutMode.compact,
    );
  });

  test('uses medium layout from tablet portrait widths', () {
    expect(
      assessmentLayoutModeForWidth(AssessmentLayoutBreakpoints.medium),
      AssessmentLayoutMode.medium,
    );
    expect(
      assessmentLayoutModeForWidth(AssessmentLayoutBreakpoints.wide - 1),
      AssessmentLayoutMode.medium,
    );
  });

  test('uses wide layout from desktop and tablet landscape widths', () {
    expect(
      assessmentLayoutModeForWidth(AssessmentLayoutBreakpoints.wide),
      AssessmentLayoutMode.wide,
    );
    expect(assessmentLayoutModeForWidth(1600), AssessmentLayoutMode.wide);
  });

  testWidgets('switches layouts without recreating assessment state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    await tester.pumpWidget(
      OpenIrnLocalizationScope(
        controller: OpenIrnLocalizations.instance,
        child: MaterialApp(
          home: AssessmentScreen(
            referential: _referential,
            campaign: _campaign,
            activeUser: _activeUser,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final initialState = tester.state(find.byType(AssessmentScreen));
    expect(find.byKey(const ValueKey('assessment-layout-compact')), findsOne);
    expect(
      find.byKey(const ValueKey('assessment-campaign-context-card')),
      findsOne,
    );
    await tester.drag(
      find.byKey(const ValueKey('assessment-layout-compact')),
      const Offset(0, -700),
    );
    await tester.pump();
    expect(
      find.byKey(const PageStorageKey<String>('assessment-pillar-pillar-1')),
      findsOne,
    );
    await tester.tap(find.text('RES-1 — Pilier 1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'compact layout overflow');

    tester.view.physicalSize = const Size(820, 1180);
    await tester.pump();
    expect(find.byKey(const ValueKey('assessment-layout-medium')), findsOne);
    expect(tester.state(find.byType(AssessmentScreen)), same(initialState));
    expect(
      tester.takeException(),
      isNull,
      reason: 'medium layout with an expanded pillar',
    );

    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pump();
    expect(find.byKey(const ValueKey('assessment-layout-wide')), findsOne);
    expect(
      find.byKey(const ValueKey('assessment-assignment-status-card')),
      findsOne,
    );
    expect(tester.state(find.byType(AssessmentScreen)), same(initialState));
    expect(
      find.byKey(const PageStorageKey<String>('assessment-pillar-pillar-1')),
      findsOne,
    );
    final firstPillarCard = tester.widget<Card>(
      find
          .descendant(
            of: find.byKey(
              const PageStorageKey<String>('assessment-pillar-pillar-1'),
            ),
            matching: find.byType(Card),
          )
          .first,
    );
    final firstPillarStyle = IrnPillarPalette.forCode('RES-1');
    expect(firstPillarCard.color, firstPillarStyle.backgroundColor);
    expect(
      (firstPillarCard.shape! as RoundedRectangleBorder).side.color,
      firstPillarStyle.borderColor,
    );
    expect(
      find.byKey(const PageStorageKey<String>('assessment-pillar-pillar-8')),
      findsNothing,
    );
    final sidebar = tester.widget<ColoredBox>(
      find.byKey(const ValueKey<String>('assessment-wide-sidebar')),
    );
    final sidebarContext = tester.element(
      find.byKey(const ValueKey<String>('assessment-wide-sidebar')),
    );
    expect(
      sidebar.color,
      Theme.of(sidebarContext).colorScheme.surfaceContainerHigh,
    );
    expect(tester.takeException(), isNull, reason: 'wide layout overflow');
  });

  testWidgets(
    'shows the simplified system card and read-only information to a reader',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });

      await tester.pumpWidget(
        OpenIrnLocalizationScope(
          controller: OpenIrnLocalizations.instance,
          child: MaterialApp(
            home: AssessmentScreen(
              referential: _referential,
              campaign: _campaign,
              activeUser: _readerUser,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final systemCard = find.byKey(
        const ValueKey('assessment-campaign-context-card'),
      );
      expect(systemCard, findsOne);
      expect(
        find.descendant(of: systemCard, matching: find.text('SI de test')),
        findsOne,
      );
      expect(
        find.descendant(
          of: systemCard,
          matching: find.text('Campagne responsive'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: systemCard, matching: find.text('Actif critique')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('assessment-assignment-status-card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('assessment-layout-compact')), findsOne);

      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Informations'));
      await tester.pumpAndSettle();

      final fields = tester.widgetList<EditableText>(find.byType(EditableText));
      expect(fields, hasLength(7));
      expect(fields.every((field) => field.readOnly), isTrue);
      expect(find.text('Actif critique'), findsOne);
      expect(find.text('Enregistrer'), findsNothing);
      expect(find.text('Fermer'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps campaign information editable for an administrator', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 1180);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    await tester.pumpWidget(
      OpenIrnLocalizationScope(
        controller: OpenIrnLocalizations.instance,
        child: MaterialApp(
          home: AssessmentScreen(
            referential: _referential,
            campaign: _campaign,
            activeUser: _activeUser,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Informations'));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields, hasLength(7));
    expect(fields.every((field) => !field.readOnly), isTrue);
    expect(find.text('Actif critique'), findsOne);
    expect(find.text('Enregistrer'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replaces the left sidebar with evaluator navigation on desktop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });

      await tester.pumpWidget(
        OpenIrnLocalizationScope(
          controller: OpenIrnLocalizations.instance,
          child: MaterialApp(
            home: AssessmentScreen(
              referential: _referential,
              campaign: _campaign,
              activeUser: _activeUser,
              showAssetScope: false,
              navigationPanel: const SizedBox(
                key: ValueKey<String>('test-evaluator-navigation'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('assessment-navigation-panel-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('assessment-navigation-panel-top')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('assessment-wide-sidebar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('assessment-campaign-context-card')),
        findsNothing,
      );
      expect(find.text('Notation par actif'), findsNothing);

      tester.view.physicalSize = const Size(900, 1000);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('assessment-navigation-panel-top')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

final _timestamp = DateTime.utc(2026, 9, 22, 10);

final _pillars = List<IrnPillar>.generate(
  8,
  (index) => IrnPillar(
    id: 'pillar-${index + 1}',
    code: 'RES-${index + 1}',
    label: 'Pilier ${index + 1}',
  ),
);

final _criteria = List<IrnCriterion>.generate(
  8,
  (index) => IrnCriterion(
    id: 'criterion-${index + 1}',
    code: 'RES-${index + 1}.1',
    sourceCode: 'RES-${index + 1}.1',
    pillarId: 'pillar-${index + 1}',
    label: 'Critère de résilience ${index + 1}',
    shortLabel: 'Critère ${index + 1}',
    description: 'Description du critère.',
    scope: CriterionScope.asset,
    sourceScope: 'Actif',
    answerMode: 'R_NR',
    regulatoryReferences: '',
    recommendations: '',
    active: true,
    source: const CriterionSourceLocation(),
  ),
);

final _referential = IrnReferential(
  id: 'referential-layout-test',
  version: 'vtest',
  source: const IrnSource(
    type: 'test',
    url: '',
    projectPath: '',
    defaultBranch: 'main',
    filePath: '',
    license: '',
  ),
  pillars: _pillars,
  criteria: _criteria,
);

final _campaign = LocalCampaign(
  id: 'campaign-layout-test',
  referentialId: _referential.id,
  name: 'Campagne responsive',
  information: CampaignInformation(
    systemName: 'SI de test',
    informationSystemId: 'system-layout-test',
    assets: <CampaignInformationAsset>[
      CampaignInformationAsset(
        id: 'asset-layout-test',
        name: 'Actif critique',
        criticality: '4',
      ),
    ],
  ),
  createdAt: _timestamp,
  updatedAt: _timestamp,
  statusUpdatedAt: _timestamp,
);

final _activeUser = AppUser(
  id: 'user-layout-test',
  firstName: 'Alice',
  lastName: 'Admin',
  email: 'alice@example.test',
  role: AppUserRole.administrator,
  active: true,
  createdAt: _timestamp,
  updatedAt: _timestamp,
);

final _readerUser = AppUser(
  id: 'reader-layout-test',
  firstName: 'Rémi',
  lastName: 'Lecteur',
  email: 'reader@example.test',
  role: AppUserRole.reader,
  active: true,
  createdAt: _timestamp,
  updatedAt: _timestamp,
);
