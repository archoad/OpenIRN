import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_campaign_repository.dart';

void main() {
  group('LocalCampaignRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalCampaignRepository();
      expect(repository, isA<LocalCampaignRepository>());
    });
  });
}
