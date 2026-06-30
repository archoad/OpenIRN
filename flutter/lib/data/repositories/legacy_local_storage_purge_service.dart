import 'package:shared_preferences/shared_preferences.dart';

class LegacyLocalStoragePurgeService {
  const LegacyLocalStoragePurgeService();

  static const Set<String> _preservedKeys = <String>{
    'openirn.sync.configuration',
    'openirn.sync.deviceId',
  };

  static const Set<String> _legacyExactKeys = <String>{
    'openirn.localUsers',
    'openirn.localSession.activeUserId',
    'openirn.sync.log.events',
    'openirn.secure.sync.configuration',
    'openirn.secure.sync.deviceId',
    'openirn.secureFallback.openirn.secure.sync.configuration',
    'openirn.secureFallback.openirn.secure.sync.deviceId',
  };

  static const List<String> _legacyPrefixes = <String>[
    'openirn.localCampaigns.',
    'openirn.assessment.answers.',
    'openirn.criterionAssignments.',
    'openirn.activityLog.',
    'openirn.secureFallback.',
  ];

  Future<LegacyLocalStoragePurgeReport> purge() async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().toList(growable: false)..sort();
    final removedKeys = <String>[];

    for (final key in keys) {
      if (_shouldRemove(key)) {
        await preferences.remove(key);
        removedKeys.add(key);
      }
    }

    return LegacyLocalStoragePurgeReport(removedKeys: removedKeys);
  }

  bool _shouldRemove(String key) {
    if (_preservedKeys.contains(key)) {
      return false;
    }
    if (_legacyExactKeys.contains(key)) {
      return true;
    }
    return _legacyPrefixes.any(key.startsWith);
  }
}

class LegacyLocalStoragePurgeReport {
  final List<String> removedKeys;

  const LegacyLocalStoragePurgeReport({required this.removedKeys});

  int get removedCount => removedKeys.length;

  bool get hasRemovedKeys => removedKeys.isNotEmpty;
}
