import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/api/openirn_api_client.dart';
import 'package:openirn/data/repositories/local_asset_evaluator_assignment_repository.dart';
import 'package:openirn/data/repositories/local_sync_configuration_repository.dart';
import 'package:openirn/data/repositories/server_campaign_store.dart';
import 'package:openirn/domain/models/irn_asset_inventory.dart';
import 'package:openirn/domain/models/sync_configuration.dart';

class _ConfigurationRepository extends LocalSyncConfigurationRepository {
  const _ConfigurationRepository();

  @override
  Future<SyncConfiguration> loadConfiguration() async =>
      SyncConfiguration.empty(
        tenantId: 'tenant-a',
        deviceId: 'device-a',
      ).copyWith(enabled: true, apiToken: 'ost_test_session');
}

class _ApiClient extends OpenIrnApiClient {
  String? assetId;
  String? userId;

  @override
  Future<OpenIrnApiInventoryResult> updateInformationAssetEvaluator({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required String assetId,
    String userId = '',
  }) async {
    this.assetId = assetId;
    this.userId = userId;
    return OpenIrnApiInventoryResult(
      status: OpenIrnApiDevicesStatus.available,
      url: 'https://example.test/api/inventory/assets/$assetId/evaluator',
      statusCode: 200,
      title: 'OK',
      message: 'OK',
      tenantId: tenantId,
      inventory: IrnAssetInventory.empty(tenantId: tenantId),
    );
  }
}

void main() {
  group('LocalAssetEvaluatorAssignmentRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalAssetEvaluatorAssignmentRepository();
      expect(repository, isA<LocalAssetEvaluatorAssignmentRepository>());
    });

    test('writes the canonical evaluator directly on the asset', () async {
      final apiClient = _ApiClient();
      final repository = LocalAssetEvaluatorAssignmentRepository(
        store: ServerCampaignStore(
          configurationRepository: const _ConfigurationRepository(),
          apiClient: apiClient,
        ),
      );

      final assignment = await repository.assignAsset(
        referentialId: 'ref-a',
        campaignId: 'campaign-a',
        assetId: 'asset-a',
        userId: 'evaluator-a',
        assignedByUserId: 'pilot-a',
      );

      expect(apiClient.assetId, 'asset-a');
      expect(apiClient.userId, 'evaluator-a');
      expect(assignment.assetId, 'asset-a');
      expect(assignment.userId, 'evaluator-a');
    });
  });
}
