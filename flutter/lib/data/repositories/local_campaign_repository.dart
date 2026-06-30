import '../../domain/models/local_campaign.dart';
import 'server_campaign_store.dart';

class LocalCampaignRepository {
  final ServerCampaignStore _store;

  const LocalCampaignRepository({ServerCampaignStore? store})
    : _store = store ?? const ServerCampaignStore();

  Future<List<LocalCampaign>> loadCampaigns({
    required String referentialId,
  }) async {
    final bundles = await _store.loadBundles(referentialId: referentialId);
    return bundles.map((bundle) => bundle.campaign).toList(growable: false);
  }

  Future<List<LocalCampaign>> ensureDefaultCampaign({
    required String referentialId,
    required String referentialVersion,
  }) {
    return loadCampaigns(referentialId: referentialId);
  }

  Future<LocalCampaign> createCampaign({
    required String referentialId,
    required String name,
    String description = '',
    CampaignInformation information = const CampaignInformation(),
  }) async {
    final bundles = await _store.loadBundles(referentialId: referentialId);
    final campaign = LocalCampaign.create(
      referentialId: referentialId,
      name: name,
      description: description,
      information: information,
    );
    await _store.saveBundles(
      referentialId: referentialId,
      bundles: <ServerCampaignBundle>[
        ServerCampaignBundle(campaign: campaign),
        ...bundles,
      ],
    );
    return campaign;
  }

  Future<void> deleteCampaign({
    required String referentialId,
    required String campaignId,
  }) async {
    final bundles = await _store.loadBundles(referentialId: referentialId);
    await _store.saveBundles(
      referentialId: referentialId,
      bundles: bundles
          .where((bundle) => bundle.campaign.id != campaignId)
          .toList(growable: false),
    );
  }

  Future<LocalCampaign?> updateCampaignInformation({
    required String referentialId,
    required String campaignId,
    String? name,
    String? description,
    required CampaignInformation information,
  }) async {
    LocalCampaign? updatedCampaign;
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) {
        final campaign = bundle.campaign;
        updatedCampaign = campaign.copyWith(
          name: name == null
              ? campaign.name
              : (name.trim().isEmpty ? campaign.name : name.trim()),
          description: description == null
              ? campaign.description
              : description.trim(),
          information: information,
          updatedAt: DateTime.now().toUtc(),
        );
        return bundle.copyWith(campaign: updatedCampaign);
      },
    );
    return updatedCampaign;
  }

  Future<LocalCampaign?> updateCampaignStatus({
    required String referentialId,
    required String campaignId,
    required LocalCampaignStatus status,
  }) async {
    LocalCampaign? updatedCampaign;
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) {
        final now = DateTime.now().toUtc();
        updatedCampaign = bundle.campaign.copyWith(
          status: status,
          updatedAt: now,
          statusUpdatedAt: now,
        );
        return bundle.copyWith(campaign: updatedCampaign);
      },
    );
    return updatedCampaign;
  }

  Future<void> touchCampaign({
    required String referentialId,
    required String campaignId,
  }) async {
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) => bundle.copyWith(
        campaign: bundle.campaign.copyWith(updatedAt: DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> saveCampaigns({
    required String referentialId,
    required List<LocalCampaign> campaigns,
  }) async {
    final existingBundles = await _store.loadBundles(
      referentialId: referentialId,
    );
    final bundlesByCampaignId = <String, ServerCampaignBundle>{
      for (final bundle in existingBundles) bundle.campaign.id: bundle,
    };

    final nextBundles = <ServerCampaignBundle>[];
    for (final campaign in campaigns) {
      if (campaign.referentialId != referentialId) {
        continue;
      }
      final existing = bundlesByCampaignId[campaign.id];
      nextBundles.add(
        existing == null
            ? ServerCampaignBundle(campaign: campaign)
            : existing.copyWith(campaign: campaign),
      );
    }

    await _store.saveBundles(
      referentialId: referentialId,
      bundles: nextBundles,
    );
  }
}
