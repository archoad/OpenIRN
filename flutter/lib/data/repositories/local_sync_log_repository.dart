import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/sync_log_event.dart';

class LocalSyncLogRepository {
  const LocalSyncLogRepository();

  static const _maxEvents = 300;
  static const _legacyStorageKey = 'openirn.sync.log.events';
  static final List<SyncLogEvent> _events = <SyncLogEvent>[];
  static bool _legacyStoragePurged = false;

  Future<List<SyncLogEvent>> loadEvents() async {
    await _purgeLegacyStorage();
    final events = _events.toList(growable: false);
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }

  Future<void> appendEvent(SyncLogEvent event) async {
    await _purgeLegacyStorage();
    _events.removeWhere((current) => current.id == event.id);
    _events.insert(0, event);
    _events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
  }

  Future<void> saveEvents(List<SyncLogEvent> events) async {
    await _purgeLegacyStorage();
    _events
      ..clear()
      ..addAll(events);
    _events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
  }

  Future<void> clear() async {
    await _purgeLegacyStorage(force: true);
    _events.clear();
  }

  Future<void> _purgeLegacyStorage({bool force = false}) async {
    if (_legacyStoragePurged && !force) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyStorageKey);
    _legacyStoragePurged = true;
  }
}
