import 'package:shared_preferences/shared_preferences.dart';

class LegacyLocalStoragePurgeService {
  const LegacyLocalStoragePurgeService();

  static const String openIrnPrefix = 'openirn.';

  static const Set<String> allowedOpenIrnKeys = <String>{
    'openirn.sync.configuration',
    'openirn.sync.deviceId',
  };

  static const Set<String> legacyExactKeys = <String>{
    'openirn.localUsers',
    'openirn.localSession.activeUserId',
    'openirn.sync.log.events',
    'openirn.secure.sync.configuration',
    'openirn.secure.sync.deviceId',
    'openirn.secureFallback.openirn.secure.sync.configuration',
    'openirn.secureFallback.openirn.secure.sync.deviceId',
  };

  static const List<String> legacyPrefixes = <String>[
    'openirn.localCampaigns.',
    'openirn.assessment.answers.',
    'openirn.criterionAssignments.',
    'openirn.activityLog.',
    'openirn.secureFallback.',
  ];

  Future<LegacyLocalStorageAuditReport> audit() async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().toList(growable: false)..sort();
    final preservedKeys = <String>[];
    final removableKeys = <String>[];
    final unexpectedOpenIrnKeys = <String>[];

    for (final key in keys) {
      if (!key.startsWith(openIrnPrefix)) {
        continue;
      }
      if (allowedOpenIrnKeys.contains(key)) {
        preservedKeys.add(key);
        continue;
      }
      removableKeys.add(key);
      if (!_isKnownLegacyKey(key)) {
        unexpectedOpenIrnKeys.add(key);
      }
    }

    return LegacyLocalStorageAuditReport(
      preservedKeys: preservedKeys,
      removableKeys: removableKeys,
      unexpectedOpenIrnKeys: unexpectedOpenIrnKeys,
    );
  }

  Future<LegacyLocalStoragePurgeReport> purge() async {
    final preferences = await SharedPreferences.getInstance();
    final auditReport = await audit();
    final removedKeys = <String>[];

    for (final key in auditReport.removableKeys) {
      await preferences.remove(key);
      removedKeys.add(key);
    }

    return LegacyLocalStoragePurgeReport(
      preservedKeys: auditReport.preservedKeys,
      removedKeys: removedKeys,
      unexpectedOpenIrnKeys: auditReport.unexpectedOpenIrnKeys,
    );
  }

  bool _isKnownLegacyKey(String key) {
    if (legacyExactKeys.contains(key)) {
      return true;
    }
    return legacyPrefixes.any(key.startsWith);
  }
}

class LegacyLocalStorageAuditReport {
  final List<String> preservedKeys;
  final List<String> removableKeys;
  final List<String> unexpectedOpenIrnKeys;

  const LegacyLocalStorageAuditReport({
    required this.preservedKeys,
    required this.removableKeys,
    required this.unexpectedOpenIrnKeys,
  });

  int get preservedCount => preservedKeys.length;

  int get removableCount => removableKeys.length;

  bool get hasRemovableKeys => removableKeys.isNotEmpty;

  bool get hasUnexpectedOpenIrnKeys => unexpectedOpenIrnKeys.isNotEmpty;
}

class LegacyLocalStoragePurgeReport {
  final List<String> preservedKeys;
  final List<String> removedKeys;
  final List<String> unexpectedOpenIrnKeys;

  const LegacyLocalStoragePurgeReport({
    required this.preservedKeys,
    required this.removedKeys,
    required this.unexpectedOpenIrnKeys,
  });

  int get preservedCount => preservedKeys.length;

  int get removedCount => removedKeys.length;

  bool get hasRemovedKeys => removedKeys.isNotEmpty;

  bool get hasUnexpectedOpenIrnKeys => unexpectedOpenIrnKeys.isNotEmpty;
}
