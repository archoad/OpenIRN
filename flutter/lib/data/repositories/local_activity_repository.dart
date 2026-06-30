import '../../domain/models/local_activity_event.dart';
import 'server_campaign_store.dart';

class LocalActivityRepository {
  final ServerCampaignStore _store;

  const LocalActivityRepository({ServerCampaignStore? store})
    : _store = store ?? const ServerCampaignStore();

  static const _maxEventsPerCampaign = 300;

  Future<List<LocalActivityEvent>> loadEvents({
    required String referentialId,
    required String campaignId,
  }) async {
    final bundle = await _store.loadBundle(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    final events = List<LocalActivityEvent>.from(
      bundle?.activityEvents ?? const <LocalActivityEvent>[],
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }

  Future<void> appendEvent(LocalActivityEvent event) async {
    final events = await loadEvents(
      referentialId: event.referentialId,
      campaignId: event.campaignId,
    );
    final updatedEvents = <LocalActivityEvent>[event, ...events]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await saveEvents(
      referentialId: event.referentialId,
      campaignId: event.campaignId,
      events: updatedEvents.take(_maxEventsPerCampaign).toList(growable: false),
    );
  }

  Future<void> saveEvents({
    required String referentialId,
    required String campaignId,
    required List<LocalActivityEvent> events,
  }) async {
    final normalizedEvents = <LocalActivityEvent>[
      for (final event in events)
        if (event.referentialId == referentialId &&
            event.campaignId == campaignId)
          event,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) => bundle.copyWith(
        activityEvents: normalizedEvents
            .take(_maxEventsPerCampaign)
            .toList(growable: false),
      ),
    );
  }

  Future<void> clearEvents({
    required String referentialId,
    required String campaignId,
  }) async {
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) =>
          bundle.copyWith(activityEvents: const <LocalActivityEvent>[]),
    );
  }
}
