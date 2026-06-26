import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_campaign_repository.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalCampaignRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('creates a default campaign for an empty referential', () async {
      const repository = LocalCampaignRepository();

      final campaigns = await repository.ensureDefaultCampaign(
        referentialId: 'adri-irn-v1.1',
        referentialVersion: 'v1.1',
      );

      expect(campaigns, hasLength(1));
      expect(campaigns.first.id, 'local-default-adri-irn-v1-1');
      expect(campaigns.first.name, contains('IRN v1.1'));
      expect(campaigns.first.status, LocalCampaignStatus.draft);
    });

    test('creates and reloads local campaigns', () async {
      const repository = LocalCampaignRepository();

      final campaign = await repository.createCampaign(
        referentialId: 'adri-irn-v1.1',
        name: 'Test IRN',
        information: const CampaignInformation(
          systemName: 'SI Achat',
          systemDescription: 'Système achat.',
          projectDirectorFirstName: 'Claire',
          projectDirectorLastName: 'Moreau',
          projectDirectorEmail: 'claire.moreau@example.test',
        ),
      );

      final campaigns = await repository.loadCampaigns(
        referentialId: 'adri-irn-v1.1',
      );

      expect(campaigns, hasLength(1));
      expect(campaigns.first.id, campaign.id);
      expect(campaigns.first.name, 'Test IRN');
      expect(campaigns.first.information.systemName, 'SI Achat');
      expect(
        campaigns.first.information.projectDirectorEmail,
        'claire.moreau@example.test',
      );
      expect(campaigns.first.status, LocalCampaignStatus.draft);
    });

    test('updates local campaign status', () async {
      const repository = LocalCampaignRepository();

      final campaign = await repository.createCampaign(
        referentialId: 'adri-irn-v1.1',
        name: 'À valider',
      );

      final updated = await repository.updateCampaignStatus(
        referentialId: 'adri-irn-v1.1',
        campaignId: campaign.id,
        status: LocalCampaignStatus.validated,
      );

      expect(updated, isNotNull);
      expect(updated!.status, LocalCampaignStatus.validated);
      expect(updated.isReadOnly, isTrue);

      final campaigns = await repository.loadCampaigns(
        referentialId: 'adri-irn-v1.1',
      );
      expect(campaigns.single.status, LocalCampaignStatus.validated);
    });

    test('updates local campaign information', () async {
      const repository = LocalCampaignRepository();

      final campaign = await repository.createCampaign(
        referentialId: 'adri-irn-v1.1',
        name: 'À documenter',
      );

      final updated = await repository.updateCampaignInformation(
        referentialId: 'adri-irn-v1.1',
        campaignId: campaign.id,
        name: 'Campagne documentée',
        description: 'Description campagne.',
        information: const CampaignInformation(
          systemName: 'SI RH',
          systemDescription: 'Système de gestion RH.',
          projectDirectorFirstName: 'Denis',
          projectDirectorLastName: 'Petit',
          projectDirectorEmail: 'denis.petit@example.test',
        ),
      );

      expect(updated, isNotNull);
      expect(updated!.name, 'Campagne documentée');
      expect(updated.information.systemName, 'SI RH');

      final campaigns = await repository.loadCampaigns(
        referentialId: 'adri-irn-v1.1',
      );
      expect(campaigns.single.description, 'Description campagne.');
      expect(
        campaigns.single.information.projectDirectorFullName,
        'Denis Petit',
      );
    });

    test('deletes one local campaign', () async {
      const repository = LocalCampaignRepository();

      final campaign = await repository.createCampaign(
        referentialId: 'adri-irn-v1.1',
        name: 'À supprimer',
      );

      await repository.deleteCampaign(
        referentialId: 'adri-irn-v1.1',
        campaignId: campaign.id,
      );

      final campaigns = await repository.loadCampaigns(
        referentialId: 'adri-irn-v1.1',
      );
      expect(campaigns, isEmpty);
    });
  });
}
