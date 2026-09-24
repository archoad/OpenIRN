import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/api/openirn_api_client.dart';
import 'package:openirn/data/repositories/local_activity_repository.dart';
import 'package:openirn/data/repositories/local_campaign_repository.dart';
import 'package:openirn/data/repositories/local_sync_configuration_repository.dart';
import 'package:openirn/domain/models/app_user.dart';
import 'package:openirn/domain/models/irn_asset_inventory.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_activity_event.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/models/sync_configuration.dart';
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
    'updates the canonical information system from campaign information',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(820, 1180);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });

      final campaignRepository = _FakeCampaignRepository(_campaign);
      final apiClient = _FakeInventoryApiClient();
      await tester.pumpWidget(
        OpenIrnLocalizationScope(
          controller: OpenIrnLocalizations.instance,
          child: MaterialApp(
            home: AssessmentScreen(
              referential: _referential,
              campaign: _campaign,
              activeUser: _activeUser,
              campaignRepository: campaignRepository,
              configurationRepository: _FakeConfigurationRepository(),
              apiClient: apiClient,
              activityRepository: _FakeActivityRepository(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Informations'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(7));
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller!.text,
        'SI canonique',
      );
      expect(
        tester.widget<TextFormField>(fields.at(4)).controller!.text,
        'Alice',
      );
      expect(
        tester.widget<TextFormField>(fields.at(5)).controller!.text,
        'Martin',
      );
      expect(
        tester.widget<TextFormField>(fields.at(6)).controller!.text,
        'alice.martin@example.test',
      );

      await tester.enterText(fields.at(2), 'SI renommé');
      await tester.enterText(fields.at(3), 'Description mise à jour');
      await tester.enterText(fields.at(4), 'Jeanne');
      await tester.enterText(fields.at(5), 'Dupont');
      await tester.enterText(fields.at(6), 'jeanne.dupont@example.test');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(apiClient.updatedSystemId, 'system-layout-test');
      expect(apiClient.updatedFunctionIds, <String>['function-layout-test']);
      expect(apiClient.updatedName, 'SI renommé');
      expect(apiClient.updatedDescription, 'Description mise à jour');
      expect(apiClient.updatedOwnerFirstName, 'Jeanne');
      expect(apiClient.updatedOwnerLastName, 'Dupont');
      expect(apiClient.updatedOwnerEmail, 'jeanne.dupont@example.test');
      expect(
        campaignRepository.updatedInformation?.projectDirectorFullName,
        'Jeanne Dupont',
      );
      expect(
        campaignRepository.updatedInformation?.projectDirectorEmail,
        'jeanne.dupont@example.test',
      );
      expect(tester.takeException(), isNull);
    },
  );

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

class _FakeCampaignRepository extends LocalCampaignRepository {
  LocalCampaign campaign;
  CampaignInformation? updatedInformation;

  _FakeCampaignRepository(this.campaign);

  @override
  Future<List<LocalCampaignData>> loadCampaignData({
    required String referentialId,
  }) async {
    return <LocalCampaignData>[
      LocalCampaignData(
        campaign: campaign,
        criterionAnswers: const {},
        assignments: const [],
      ),
    ];
  }

  @override
  Future<LocalCampaign?> updateCampaignInformation({
    required String referentialId,
    required String campaignId,
    String? name,
    String? description,
    required CampaignInformation information,
  }) async {
    updatedInformation = information;
    campaign = campaign.copyWith(
      name: name,
      description: description,
      information: information,
      updatedAt: _timestamp.add(const Duration(minutes: 1)),
    );
    return campaign;
  }
}

class _FakeConfigurationRepository extends LocalSyncConfigurationRepository {
  @override
  Future<SyncConfiguration> loadConfiguration() async {
    return SyncConfiguration(
      apiBaseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: 'tenant-layout-test',
      deviceId: 'device-layout-test',
      enabled: true,
      apiToken: 'ost_layout_test',
      updatedAt: _timestamp,
    );
  }
}

class _FakeActivityRepository extends LocalActivityRepository {
  @override
  Future<void> appendEvent(LocalActivityEvent event) async {}
}

class _FakeInventoryApiClient extends OpenIrnApiClient {
  String? updatedSystemId;
  List<String>? updatedFunctionIds;
  String? updatedName;
  String? updatedDescription;
  String? updatedOwnerFirstName;
  String? updatedOwnerLastName;
  String? updatedOwnerEmail;

  IrnAssetInventory inventory = IrnAssetInventory(
    tenantId: 'tenant-layout-test',
    tenantDisplayName: 'Tenant test',
    criticalFunctions: const [],
    informationSystems: const <InformationSystemInfo>[
      InformationSystemInfo(
        id: 'system-layout-test',
        tenantId: 'tenant-layout-test',
        functionIds: <String>['function-layout-test'],
        name: 'SI canonique',
        description: 'Description canonique',
        owner: 'Alice Martin',
        ownerFirstName: 'Alice',
        ownerLastName: 'Martin',
        ownerEmail: 'alice.martin@example.test',
      ),
    ],
    assets: const <InformationAssetInfo>[
      InformationAssetInfo(
        id: 'asset-layout-test',
        tenantId: 'tenant-layout-test',
        systemIds: <String>['system-layout-test'],
        name: 'Actif critique',
        assetType: 'Application',
        description: '',
        criticality: '4',
      ),
    ],
  );

  OpenIrnApiInventoryResult _result() {
    return OpenIrnApiInventoryResult(
      status: OpenIrnApiDevicesStatus.available,
      url: 'https://www.archoad.io/api/inventory',
      statusCode: 200,
      title: 'Inventaire',
      message: 'OK',
      tenantId: inventory.tenantId,
      inventory: inventory,
    );
  }

  @override
  Future<OpenIrnApiInventoryResult> loadAssetInventory({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async => _result();

  @override
  Future<OpenIrnApiInventoryResult> updateInformationSystem({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required String systemId,
    List<String> functionIds = const <String>[],
    required String name,
    String description = '',
    String owner = '',
    String ownerFirstName = '',
    String ownerLastName = '',
    String ownerEmail = '',
  }) async {
    updatedSystemId = systemId;
    updatedFunctionIds = List<String>.from(functionIds);
    updatedName = name;
    updatedDescription = description;
    updatedOwnerFirstName = ownerFirstName;
    updatedOwnerLastName = ownerLastName;
    updatedOwnerEmail = ownerEmail;
    inventory = IrnAssetInventory(
      tenantId: inventory.tenantId,
      tenantDisplayName: inventory.tenantDisplayName,
      criticalFunctions: inventory.criticalFunctions,
      informationSystems: <InformationSystemInfo>[
        InformationSystemInfo(
          id: systemId,
          tenantId: tenantId,
          functionIds: functionIds,
          name: name,
          description: description,
          owner: '$ownerFirstName $ownerLastName'.trim(),
          ownerFirstName: ownerFirstName,
          ownerLastName: ownerLastName,
          ownerEmail: ownerEmail,
        ),
      ],
      assets: inventory.assets,
    );
    return _result();
  }
}
