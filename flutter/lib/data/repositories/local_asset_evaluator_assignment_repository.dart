import '../../domain/models/asset_evaluator_assignment.dart';
import 'server_campaign_store.dart';

class LocalAssetEvaluatorAssignmentRepository {
  final ServerCampaignStore _store;

  const LocalAssetEvaluatorAssignmentRepository({ServerCampaignStore? store})
    : _store = store ?? const ServerCampaignStore();

  Future<List<AssetEvaluatorAssignment>> loadAssignments({
    required String referentialId,
    required String campaignId,
  }) async {
    final bundle = await _store.loadBundle(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    return List<AssetEvaluatorAssignment>.from(
      bundle?.assignments ?? const <AssetEvaluatorAssignment>[],
    )..sort((a, b) => a.assetId.compareTo(b.assetId));
  }

  Future<Map<String, AssetEvaluatorAssignment>> loadAssignmentsByAsset({
    required String referentialId,
    required String campaignId,
  }) async {
    final assignments = await loadAssignments(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    return <String, AssetEvaluatorAssignment>{
      for (final assignment in assignments) assignment.assetId: assignment,
    };
  }

  Future<AssetEvaluatorAssignment> assignAsset({
    required String referentialId,
    required String campaignId,
    required String assetId,
    required String userId,
    String assignedByUserId = '',
  }) async {
    await _updateCanonicalAssignment(assetId: assetId, userId: userId);
    return AssetEvaluatorAssignment.create(
      referentialId: referentialId,
      campaignId: campaignId,
      assetId: assetId,
      userId: userId,
      assignedByUserId: assignedByUserId,
    );
  }

  Future<void> clearAssignment({required String assetId}) async {
    await _updateCanonicalAssignment(assetId: assetId, userId: '');
  }

  Future<void> _updateCanonicalAssignment({
    required String assetId,
    required String userId,
  }) async {
    final configuration = await _store.configurationRepository
        .loadConfiguration();
    if (!configuration.isConfigured) {
      throw const ServerCampaignStoreException(
        'Terminal non autorisé : impossible de modifier l’évaluateur de l’actif.',
      );
    }
    final result = await _store.apiClient.updateInformationAssetEvaluator(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
      assetId: assetId,
      userId: userId,
    );
    if (!result.isAvailable) {
      throw ServerCampaignStoreException('${result.title} — ${result.message}');
    }
  }
}
