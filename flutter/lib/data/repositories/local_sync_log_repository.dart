import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/sync_log_event.dart';

class LocalSyncLogRepository {
  const LocalSyncLogRepository();

  static const _schemaVersion = 1;
  static const _maxEvents = 300;
  static const _storageKey = 'openirn.sync.log.events';

  Future<List<SyncLogEvent>> loadEvents() async {
    final preferences = await SharedPreferences.getInstance();
    final rawPayload = preferences.getString(_storageKey);
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return const <SyncLogEvent>[];
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return const <SyncLogEvent>[];
      }
      final rawEvents = decoded['events'];
      if (rawEvents is! List) {
        return const <SyncLogEvent>[];
      }
      final events = rawEvents
          .whereType<Map>()
          .map((item) => SyncLogEvent.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return events;
    } on FormatException {
      return const <SyncLogEvent>[];
    }
  }

  Future<void> appendEvent(SyncLogEvent event) async {
    final currentEvents = await loadEvents();
    final nextEvents = <SyncLogEvent>[
      event,
      ...currentEvents.where((current) => current.id != event.id),
    ];
    await saveEvents(nextEvents.take(_maxEvents).toList(growable: false));
  }

  Future<void> saveEvents(List<SyncLogEvent> events) async {
    final preferences = await SharedPreferences.getInstance();
    final sortedEvents = [...events]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'retentionPolicy': 'local_last_${_maxEvents}_sync_events',
      'events': sortedEvents
          .take(_maxEvents)
          .map((event) => event.toJson())
          .toList(growable: false),
    };
    await preferences.setString(_storageKey, jsonEncode(payload));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}
