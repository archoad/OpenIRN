import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_activity_repository.dart';
import 'package:openirn/domain/models/local_activity_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalActivityRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('appends and reloads events for one campaign', () async {
      const repository = LocalActivityRepository();

      await repository.appendEvent(
        LocalActivityEvent.create(
          referentialId: 'adri-irn-v1.1',
          campaignId: 'campaign-a',
          type: LocalActivityType.answerChanged,
          title: 'Réponse modifiée',
          description: 'RES-1.1 — Test',
          criterionId: 'RES-1.1',
          fromValue: 'N.C.',
          toValue: 'R',
          now: DateTime.utc(2026, 6, 22, 10),
        ),
      );

      final events = await repository.loadEvents(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );

      expect(events, hasLength(1));
      expect(events.single.type, LocalActivityType.answerChanged);
      expect(events.single.criterionId, 'RES-1.1');
      expect(events.single.fromValue, 'N.C.');
      expect(events.single.toValue, 'R');
    });

    test('isolates events by campaign', () async {
      const repository = LocalActivityRepository();

      await repository.appendEvent(
        LocalActivityEvent.create(
          referentialId: 'adri-irn-v1.1',
          campaignId: 'campaign-a',
          type: LocalActivityType.campaignCreated,
          title: 'Campagne A',
        ),
      );
      await repository.appendEvent(
        LocalActivityEvent.create(
          referentialId: 'adri-irn-v1.1',
          campaignId: 'campaign-b',
          type: LocalActivityType.campaignCreated,
          title: 'Campagne B',
        ),
      );

      final first = await repository.loadEvents(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );
      final second = await repository.loadEvents(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-b',
      );

      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(first.single.title, 'Campagne A');
      expect(second.single.title, 'Campagne B');
    });

    test('keeps newest events first', () async {
      const repository = LocalActivityRepository();

      await repository.appendEvent(
        LocalActivityEvent.create(
          referentialId: 'adri-irn-v1.1',
          campaignId: 'campaign-a',
          type: LocalActivityType.answerChanged,
          title: 'Ancien',
          now: DateTime.utc(2026, 6, 22, 10),
        ),
      );
      await repository.appendEvent(
        LocalActivityEvent.create(
          referentialId: 'adri-irn-v1.1',
          campaignId: 'campaign-a',
          type: LocalActivityType.answerChanged,
          title: 'Récent',
          now: DateTime.utc(2026, 6, 22, 11),
        ),
      );

      final events = await repository.loadEvents(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );

      expect(events.map((event) => event.title), <String>['Récent', 'Ancien']);
    });
  });
}
