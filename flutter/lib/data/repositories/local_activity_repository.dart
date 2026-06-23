import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/local_activity_event.dart';

class LocalActivityRepository {
  const LocalActivityRepository();

  static const _schemaVersion = 1;
  static const _keyPrefix = 'openirn.activityLog';
  static const _maxEventsPerCampaign = 300;

  Future<List<LocalActivityEvent>> loadEvents({
    required String referentialId,
    required String campaignId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final rawPayload =
        preferences.getString(_storageKey(referentialId, campaignId));
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return <LocalActivityEvent>[];
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return <LocalActivityEvent>[];
      }

      final rawEvents = decoded['events'];
      if (rawEvents is! List) {
        return <LocalActivityEvent>[];
      }

      final events = <LocalActivityEvent>[];
      for (final rawEvent in rawEvents) {
        if (rawEvent is! Map) {
          continue;
        }
        final event =
            LocalActivityEvent.fromJson(Map<String, dynamic>.from(rawEvent));
        if (event.id.isEmpty ||
            event.referentialId != referentialId ||
            event.campaignId != campaignId) {
          continue;
        }
        events.add(event);
      }

      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return events;
    } on FormatException {
      return <LocalActivityEvent>[];
    }
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
    final preferences = await SharedPreferences.getInstance();
    final normalizedEvents = <LocalActivityEvent>[
      for (final event in events)
        if (event.referentialId == referentialId &&
            event.campaignId == campaignId)
          event,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'referentialId': referentialId,
      'campaignId': campaignId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'events': normalizedEvents
          .take(_maxEventsPerCampaign)
          .map((event) => event.toJson())
          .toList(growable: false),
    };

    await preferences.setString(
        _storageKey(referentialId, campaignId), jsonEncode(payload));
  }

  Future<void> clearEvents({
    required String referentialId,
    required String campaignId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey(referentialId, campaignId));
  }

  String _storageKey(String referentialId, String campaignId) {
    return '$_keyPrefix.$referentialId.$campaignId';
  }
}
