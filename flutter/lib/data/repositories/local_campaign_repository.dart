import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/local_campaign.dart';
import 'server_campaign_store.dart';

class LocalCampaignData {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final List<CriterionAssignment> assignments;

  const LocalCampaignData({
    required this.campaign,
    required this.criterionAnswers,
    required this.assignments,
  });
}

class LocalCampaignRepository {
  final ServerCampaignStore _store;

  const LocalCampaignRepository({ServerCampaignStore? store})
    : _store = store ?? const ServerCampaignStore();

  Future<List<LocalCampaign>> loadCampaigns({
    required String referentialId,
  }) async {
    final campaignData = await loadCampaignData(referentialId: referentialId);
    return campaignData.map((data) => data.campaign).toList(growable: false);
  }

  Future<List<LocalCampaignData>> loadCampaignData({
    required String referentialId,
  }) async {
    final bundles = await _store.loadBundles(referentialId: referentialId);
    return bundles
        .map(
          (bundle) => LocalCampaignData(
            campaign: bundle.campaign,
            criterionAnswers: Map<String, CriterionAnswer>.unmodifiable(
              bundle.criterionAnswers,
            ),
            assignments: List<CriterionAssignment>.unmodifiable(
              bundle.assignments,
            ),
          ),
        )
        .toList(growable: false);
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
    final campaign = LocalCampaign.create(
      referentialId: referentialId,
      name: name,
      description: description,
      information: information,
    );
    await _store.saveBundles(
      referentialId: referentialId,
      bundles: <ServerCampaignBundle>[ServerCampaignBundle(campaign: campaign)],
    );
    return campaign;
  }

  Future<void> deleteCampaign({
    required String referentialId,
    required String campaignId,
  }) async {
    await _store.deleteBundle(
      referentialId: referentialId,
      campaignId: campaignId,
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
