import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/local_campaign.dart';

class LocalCampaignRepository {
  const LocalCampaignRepository();

  static const _schemaVersion = 3;
  static const _keyPrefix = 'openirn.localCampaigns';

  Future<List<LocalCampaign>> loadCampaigns(
      {required String referentialId}) async {
    final preferences = await SharedPreferences.getInstance();
    final rawPayload = preferences.getString(_storageKey(referentialId));
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return <LocalCampaign>[];
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return <LocalCampaign>[];
      }

      final rawCampaigns = decoded['campaigns'];
      if (rawCampaigns is! List) {
        return <LocalCampaign>[];
      }

      final campaigns = <LocalCampaign>[];
      for (final rawCampaign in rawCampaigns) {
        if (rawCampaign is! Map) {
          continue;
        }
        final campaign =
            LocalCampaign.fromJson(Map<String, dynamic>.from(rawCampaign));
        if (campaign.id.isEmpty || campaign.referentialId != referentialId) {
          continue;
        }
        campaigns.add(campaign);
      }

      campaigns.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return campaigns;
    } on FormatException {
      return <LocalCampaign>[];
    }
  }

  Future<List<LocalCampaign>> ensureDefaultCampaign({
    required String referentialId,
    required String referentialVersion,
  }) async {
    final campaigns = await loadCampaigns(referentialId: referentialId);
    if (campaigns.isNotEmpty) {
      return campaigns;
    }

    final defaultCampaign = LocalCampaign.defaultForReferential(
      referentialId: referentialId,
      referentialVersion: referentialVersion,
    );
    await saveCampaigns(
        referentialId: referentialId,
        campaigns: <LocalCampaign>[defaultCampaign]);
    return <LocalCampaign>[defaultCampaign];
  }

  Future<LocalCampaign> createCampaign({
    required String referentialId,
    required String name,
    String description = '',
    CampaignInformation information = const CampaignInformation(),
  }) async {
    final campaigns = await loadCampaigns(referentialId: referentialId);
    final campaign = LocalCampaign.create(
      referentialId: referentialId,
      name: name,
      description: description,
      information: information,
    );

    await saveCampaigns(
      referentialId: referentialId,
      campaigns: <LocalCampaign>[campaign, ...campaigns],
    );
    return campaign;
  }

  Future<void> deleteCampaign({
    required String referentialId,
    required String campaignId,
  }) async {
    final campaigns = await loadCampaigns(referentialId: referentialId);
    final remaining = campaigns
        .where((campaign) => campaign.id != campaignId)
        .toList(growable: false);
    await saveCampaigns(referentialId: referentialId, campaigns: remaining);
  }

  Future<LocalCampaign?> updateCampaignInformation({
    required String referentialId,
    required String campaignId,
    String? name,
    String? description,
    required CampaignInformation information,
  }) async {
    final campaigns = await loadCampaigns(referentialId: referentialId);
    final now = DateTime.now().toUtc();
    LocalCampaign? updatedCampaign;
    final updatedCampaigns = <LocalCampaign>[];

    for (final campaign in campaigns) {
      if (campaign.id == campaignId) {
        updatedCampaign = campaign.copyWith(
          name: name == null
              ? campaign.name
              : (name.trim().isEmpty ? campaign.name : name.trim()),
          description:
              description == null ? campaign.description : description.trim(),
          information: information,
          updatedAt: now,
        );
        updatedCampaigns.add(updatedCampaign);
      } else {
        updatedCampaigns.add(campaign);
      }
    }

    if (updatedCampaign == null) {
      return null;
    }

    await saveCampaigns(
        referentialId: referentialId, campaigns: updatedCampaigns);
    return updatedCampaign;
  }

  Future<LocalCampaign?> updateCampaignStatus({
    required String referentialId,
    required String campaignId,
    required LocalCampaignStatus status,
  }) async {
    final campaigns = await loadCampaigns(referentialId: referentialId);
    final now = DateTime.now().toUtc();
    LocalCampaign? updatedCampaign;
    final updatedCampaigns = <LocalCampaign>[];

    for (final campaign in campaigns) {
      if (campaign.id == campaignId) {
        updatedCampaign = campaign.copyWith(
          status: status,
          updatedAt: now,
          statusUpdatedAt: now,
        );
        updatedCampaigns.add(updatedCampaign);
      } else {
        updatedCampaigns.add(campaign);
      }
    }

    if (updatedCampaign == null) {
      return null;
    }

    await saveCampaigns(
        referentialId: referentialId, campaigns: updatedCampaigns);
    return updatedCampaign;
  }

  Future<void> touchCampaign({
    required String referentialId,
    required String campaignId,
  }) async {
    final campaigns = await loadCampaigns(referentialId: referentialId);
    final now = DateTime.now().toUtc();
    final updatedCampaigns = <LocalCampaign>[
      for (final campaign in campaigns)
        campaign.id == campaignId
            ? campaign.copyWith(updatedAt: now)
            : campaign,
    ];
    await saveCampaigns(
        referentialId: referentialId, campaigns: updatedCampaigns);
  }

  Future<void> saveCampaigns({
    required String referentialId,
    required List<LocalCampaign> campaigns,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'referentialId': referentialId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'campaigns': <Map<String, dynamic>>[
        for (final campaign in campaigns)
          if (campaign.referentialId == referentialId) campaign.toJson(),
      ],
    };

    await preferences.setString(
        _storageKey(referentialId), jsonEncode(payload));
  }

  String _storageKey(String referentialId) {
    return '$_keyPrefix.$referentialId';
  }
}
