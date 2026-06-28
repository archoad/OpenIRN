import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/sync_configuration.dart';

class LocalSyncConfigurationRepository {
  const LocalSyncConfigurationRepository();

  static const _schemaVersion = 3;
  static const _configurationKey = 'openirn.sync.configuration';
  static const _deviceIdKey = 'openirn.sync.deviceId';

  Future<SyncConfiguration> loadConfiguration() async {
    final preferences = await SharedPreferences.getInstance();
    final deviceId = await _ensureDeviceId(preferences);
    final rawPayload = preferences.getString(_configurationKey);

    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return SyncConfiguration.empty(deviceId: deviceId);
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return SyncConfiguration.empty(deviceId: deviceId);
      }

      final rawConfiguration = decoded['configuration'];
      if (rawConfiguration is! Map) {
        return SyncConfiguration.empty(deviceId: deviceId);
      }

      final configuration = SyncConfiguration.fromJson(
        Map<String, dynamic>.from(rawConfiguration),
      ).copyWith(apiBaseUrl: SyncConfiguration.fixedApiBaseUrl);
      if (configuration.deviceId.trim().isEmpty) {
        return configuration.copyWith(deviceId: deviceId);
      }
      return configuration;
    } on FormatException {
      return SyncConfiguration.empty(deviceId: deviceId);
    }
  }

  Future<SyncConfiguration> saveConfiguration(
    SyncConfiguration configuration,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final deviceId = configuration.deviceId.trim().isEmpty
        ? await _ensureDeviceId(preferences)
        : configuration.deviceId.trim();
    final tenantId = configuration.tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : configuration.tenantId.trim();
    final updated = configuration.copyWith(
      apiBaseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: tenantId,
      deviceId: deviceId,
      updatedAt: DateTime.now().toUtc(),
    );

    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'updatedAt': updated.updatedAt.toUtc().toIso8601String(),
      'configuration': updated.toJson(),
    };

    await preferences.setString(_deviceIdKey, updated.deviceId);
    await preferences.setString(_configurationKey, jsonEncode(payload));
    return updated;
  }

  Future<String> resetDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final deviceId = _generateDeviceId();
    await preferences.setString(_deviceIdKey, deviceId);
    final configuration = await loadConfiguration();
    await saveConfiguration(configuration.copyWith(deviceId: deviceId));
    return deviceId;
  }

  Future<String> _ensureDeviceId(SharedPreferences preferences) async {
    final stored = preferences.getString(_deviceIdKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final generated = _generateDeviceId();
    await preferences.setString(_deviceIdKey, generated);
    return generated;
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final suffix = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'openirn-$timestamp-$suffix';
  }
}
