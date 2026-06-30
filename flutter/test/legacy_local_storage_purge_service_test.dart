import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/legacy_local_storage_purge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'purges legacy business data and preserves public device metadata',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'openirn.sync.configuration': '{}',
        'openirn.sync.deviceId': 'device-1',
        'openirn.localUsers': '{"users":[]}',
        'openirn.localSession.activeUserId': 'admin',
        'openirn.localCampaigns.adri-irn': '[]',
        'openirn.assessment.answers.adri-irn.campaign-1': '{}',
        'openirn.criterionAssignments.adri-irn.campaign-1': '[]',
        'openirn.activityLog.adri-irn.campaign-1': '[]',
        'openirn.sync.log.events': '[]',
        'openirn.secureFallback.openirn.secure.sync.configuration': '{}',
        'unrelated.preference': 'kept',
      });

      final report = await const LegacyLocalStoragePurgeService().purge();
      final preferences = await SharedPreferences.getInstance();

      expect(report.removedCount, 8);
      expect(preferences.getString('openirn.sync.configuration'), '{}');
      expect(preferences.getString('openirn.sync.deviceId'), 'device-1');
      expect(preferences.getString('unrelated.preference'), 'kept');
      expect(preferences.containsKey('openirn.localUsers'), isFalse);
      expect(
        preferences.containsKey('openirn.localSession.activeUserId'),
        isFalse,
      );
      expect(
        preferences.containsKey('openirn.localCampaigns.adri-irn'),
        isFalse,
      );
      expect(
        preferences.containsKey(
          'openirn.assessment.answers.adri-irn.campaign-1',
        ),
        isFalse,
      );
      expect(
        preferences.containsKey(
          'openirn.criterionAssignments.adri-irn.campaign-1',
        ),
        isFalse,
      );
      expect(
        preferences.containsKey('openirn.activityLog.adri-irn.campaign-1'),
        isFalse,
      );
      expect(preferences.containsKey('openirn.sync.log.events'), isFalse);
      expect(
        preferences.containsKey(
          'openirn.secureFallback.openirn.secure.sync.configuration',
        ),
        isFalse,
      );
    },
  );
}
