import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/sync_configuration.dart';
import '../../domain/services/app_session_manager.dart';

class LocalSyncConfigurationRepository {
  const LocalSyncConfigurationRepository();

  static const _schemaVersion = 5;
  static const _configurationKey = 'openirn.sync.configuration';
  static const _deviceIdKey = 'openirn.sync.deviceId';
  static const _legacySecureFallbackConfigurationKey =
      'openirn.secureFallback.openirn.secure.sync.configuration';
  static const _legacySecureFallbackDeviceIdKey =
      'openirn.secureFallback.openirn.secure.sync.deviceId';

  Future<SyncConfiguration> loadConfiguration() async {
    final preferences = await SharedPreferences.getInstance();
    final configuration = await _loadPublicConfiguration(preferences);
    final normalized = await _ensurePublicDeviceContext(
      preferences,
      configuration,
    );

    final sessionManager = AppSessionManager.instance;
    sessionManager.updateDeviceContext(
      tenantId: sessionManager.hasActiveSession
          ? sessionManager.tenantId
          : normalized.tenantId,
      deviceId: normalized.deviceId,
    );

    return normalized.copyWith(apiToken: AppSessionManager.instance.apiToken);
  }

  Future<SyncConfiguration> saveConfiguration(
    SyncConfiguration configuration,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final existing = await _loadPublicConfiguration(preferences);
    final deviceId = configuration.deviceId.trim().isEmpty
        ? existing.deviceId.trim().isEmpty
              ? _generateDeviceId()
              : existing.deviceId.trim()
        : configuration.deviceId.trim();
    final tenantId = configuration.tenantId.trim();
    final sessionToken = configuration.apiToken.trim();

    final publicConfiguration = configuration.copyWith(
      apiBaseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: tenantId,
      deviceId: deviceId,
      apiToken: '',
      updatedAt: DateTime.now().toUtc(),
    );

    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'updatedAt': publicConfiguration.updatedAt.toUtc().toIso8601String(),
      'storage': 'public_device_metadata',
      'configuration': publicConfiguration.toJson(),
    };

    await preferences.setString(_deviceIdKey, publicConfiguration.deviceId);
    await preferences.setString(_configurationKey, jsonEncode(payload));
    await _deleteLegacySecureFallback(preferences);

    AppSessionManager.instance.updateDeviceContext(
      tenantId: publicConfiguration.tenantId,
      deviceId: publicConfiguration.deviceId,
    );

    if (sessionToken.isNotEmpty) {
      final sessionManager = AppSessionManager.instance;
      final preservedUser = sessionManager.activeUser;
      final preservedSessionId = sessionManager.sessionId;
      final preservedExpiresAt = sessionManager.expiresAt;
      final preservedIdleTimeout = sessionManager.idleTimeout;
      sessionManager.startSession(
        apiToken: sessionToken,
        tenantId: publicConfiguration.tenantId,
        deviceId: publicConfiguration.deviceId,
        sessionId: preservedSessionId,
        expiresAt:
            preservedExpiresAt ??
            DateTime.now().toUtc().add(const Duration(hours: 8)),
        idleTimeout: preservedIdleTimeout,
        activeUser: preservedUser,
      );
    } else {
      AppSessionManager.instance.clearSession();
    }

    return publicConfiguration.copyWith(
      apiToken: AppSessionManager.instance.apiToken,
    );
  }

  Future<SyncConfiguration> saveTenantSelectionForSolutionAdministration(
    SyncConfiguration configuration,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final existing = await _loadPublicConfiguration(preferences);
    final deviceId = configuration.deviceId.trim().isEmpty
        ? existing.deviceId.trim().isEmpty
              ? _generateDeviceId()
              : existing.deviceId.trim()
        : configuration.deviceId.trim();
    final publicConfiguration = configuration.copyWith(
      apiBaseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: configuration.tenantId.trim(),
      deviceId: deviceId,
      apiToken: '',
      updatedAt: DateTime.now().toUtc(),
    );

    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'updatedAt': publicConfiguration.updatedAt.toUtc().toIso8601String(),
      'storage': 'public_device_metadata',
      'configuration': publicConfiguration.toJson(),
    };

    await preferences.setString(_deviceIdKey, publicConfiguration.deviceId);
    await preferences.setString(_configurationKey, jsonEncode(payload));
    await _deleteLegacySecureFallback(preferences);

    return publicConfiguration.copyWith(
      apiToken: AppSessionManager.instance.apiToken,
    );
  }

  Future<String> resetDeviceId() async {
    final configuration = await loadConfiguration();
    final deviceId = _generateDeviceId();
    final updated = await saveConfiguration(
      configuration.copyWith(deviceId: deviceId, apiToken: ''),
    );
    return updated.deviceId;
  }

  Future<SyncConfiguration> clearTenantSelection() async {
    final configuration = await loadConfiguration();
    return saveConfiguration(
      configuration.copyWith(tenantId: '', enabled: false, apiToken: ''),
    );
  }

  Future<SyncConfiguration> _loadPublicConfiguration(
    SharedPreferences preferences,
  ) async {
    final rawPayload =
        preferences.getString(_configurationKey) ??
        preferences.getString(_legacySecureFallbackConfigurationKey);
    final fallbackDeviceId =
        preferences.getString(_deviceIdKey) ??
        preferences.getString(_legacySecureFallbackDeviceIdKey);

    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return SyncConfiguration.empty(deviceId: fallbackDeviceId ?? '');
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return SyncConfiguration.empty(deviceId: fallbackDeviceId ?? '');
      }

      final rawConfiguration = decoded['configuration'];
      if (rawConfiguration is! Map) {
        return SyncConfiguration.empty(deviceId: fallbackDeviceId ?? '');
      }

      final configuration = SyncConfiguration.fromJson(
        Map<String, dynamic>.from(rawConfiguration),
      ).copyWith(apiBaseUrl: SyncConfiguration.fixedApiBaseUrl, apiToken: '');

      if (configuration.deviceId.trim().isNotEmpty) {
        return configuration;
      }

      return configuration.copyWith(deviceId: fallbackDeviceId ?? '');
    } on FormatException {
      return SyncConfiguration.empty(deviceId: fallbackDeviceId ?? '');
    }
  }

  Future<SyncConfiguration> _ensurePublicDeviceContext(
    SharedPreferences preferences,
    SyncConfiguration configuration,
  ) async {
    final deviceId = configuration.deviceId.trim().isEmpty
        ? _generateDeviceId()
        : configuration.deviceId.trim();
    final tenantId = configuration.tenantId.trim();
    final normalized = configuration.copyWith(
      apiBaseUrl: SyncConfiguration.fixedApiBaseUrl,
      tenantId: tenantId,
      deviceId: deviceId,
      apiToken: '',
    );

    await preferences.setString(_deviceIdKey, normalized.deviceId);
    await _deleteLegacySecureFallback(preferences);
    return normalized;
  }

  Future<void> _deleteLegacySecureFallback(
    SharedPreferences preferences,
  ) async {
    await preferences.remove(_legacySecureFallbackConfigurationKey);
    await preferences.remove(_legacySecureFallbackDeviceIdKey);
    await preferences.remove(
      'openirn.secureFallback.openirn.secure.sync.deviceId',
    );
    await preferences.remove(
      'openirn.secureFallback.openirn.secure.sync.configuration',
    );
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
