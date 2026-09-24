import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_asset_inventory.dart';
import 'package:openirn/presentation/campaigns/campaign_management_screen.dart';

void main() {
  test('an asset can belong to several systems and functions', () {
    final inventory = IrnAssetInventory.fromJson(<String, dynamic>{
      'tenantId': 'tenant-a',
      'criticalFunctions': <Map<String, dynamic>>[
        <String, dynamic>{'functionId': 'function-a', 'name': 'A'},
        <String, dynamic>{'functionId': 'function-b', 'name': 'B'},
      ],
      'informationSystems': <Map<String, dynamic>>[
        <String, dynamic>{
          'systemId': 'system-a',
          'functionIds': <String>['function-a', 'function-b'],
          'name': 'SI partagé',
        },
        <String, dynamic>{
          'systemId': 'system-b',
          'functionIds': <String>['function-b'],
          'name': 'SI B',
        },
      ],
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'assetId': 'asset-db',
          'systemIds': <String>['system-a', 'system-b'],
          'name': 'Base de données',
          'criticality': '4',
          'assessmentAnswerCount': 42,
        },
      ],
    });

    expect(inventory.systemsForFunction('function-a'), hasLength(1));
    expect(inventory.systemsForFunction('function-b'), hasLength(2));
    expect(inventory.assetsForSystem('system-a').single.id, 'asset-db');
    expect(inventory.assetsForSystem('system-b').single.id, 'asset-db');
    expect(inventory.assets.single.systemIds, <String>['system-a', 'system-b']);
    expect(inventory.assets.single.isAssessed, isTrue);
  });

  test('legacy singular relationships remain readable', () {
    final inventory = IrnAssetInventory.fromJson(<String, dynamic>{
      'informationSystems': <Map<String, dynamic>>[
        <String, dynamic>{
          'systemId': 'system-a',
          'functionId': 'function-a',
          'name': 'SI A',
        },
      ],
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'assetId': 'asset-a',
          'systemId': 'system-a',
          'name': 'Actif A',
        },
      ],
    });

    expect(inventory.informationSystems.single.functionIds, ['function-a']);
    expect(inventory.assets.single.systemIds, ['system-a']);
  });

  test('system owner identity is structured and copied into campaigns', () {
    final inventory = IrnAssetInventory.fromJson(<String, dynamic>{
      'informationSystems': <Map<String, dynamic>>[
        <String, dynamic>{
          'systemId': 'system-a',
          'name': 'SI A',
          'description': 'Description SI',
          'owner': 'Alice Martin',
          'ownerFirstName': 'Alice',
          'ownerLastName': 'Martin',
          'ownerEmail': 'ALICE.MARTIN@EXAMPLE.TEST',
        },
      ],
    });
    final system = inventory.informationSystems.single;

    expect(system.ownerFullName, 'Alice Martin');
    expect(system.ownerEmail, 'alice.martin@example.test');
    expect(
      system.ownerDisplayLabel,
      'Alice Martin <alice.martin@example.test>',
    );

    final campaignInformation = campaignInformationFromInventorySystem(
      system: system,
      functions: const <CriticalFunctionInfo>[],
      assets: const <InformationAssetInfo>[],
    );
    expect(campaignInformation.projectDirectorFirstName, 'Alice');
    expect(campaignInformation.projectDirectorLastName, 'Martin');
    expect(
      campaignInformation.projectDirectorEmail,
      'alice.martin@example.test',
    );
  });

  test('legacy owner remains readable as the last name', () {
    final system = InformationSystemInfo.fromJson(<String, dynamic>{
      'systemId': 'system-legacy',
      'name': 'SI historique',
      'owner': 'Porteur historique',
    });

    expect(system.ownerFirstName, isEmpty);
    expect(system.ownerLastName, 'Porteur historique');
    expect(system.ownerFullName, 'Porteur historique');
  });
}
