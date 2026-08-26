import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/sync_configuration.dart';
import '../../domain/services/app_session_manager.dart';

class LocalSyncConfigurationRepository {
  final FlutterSecureStorage _secureStorage;

  const LocalSyncConfigurationRepository({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secureStorage = secureStorage;

  static const _schemaVersion = 6;
  static const _configurationKey = 'openirn.sync.configuration';
  static const _deviceIdKey = 'openirn.sync.deviceId';
  static const _deviceCredentialsKey = 'openirn.secure.deviceCredentials.v2';
  static const _legacyDeviceCredentialKey =
      'openirn.secure.deviceCredential.v1';
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
    if (!sessionManager.hasActiveSession) {
      sessionManager.updateDeviceContext(
        tenantId: normalized.tenantId,
        deviceId: normalized.deviceId,
      );
      final credential = await _readDeviceCredential(normalized);
      if (credential != null) {
        sessionManager.setDeviceCredential(
          apiToken: credential.apiToken,
          tenantId: normalized.tenantId,
          deviceId: normalized.deviceId,
        );
      } else {
        sessionManager.clearDeviceCredential();
      }
    }

    return normalized.copyWith(apiToken: sessionManager.apiToken);
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
    final suppliedToken = configuration.apiToken.trim();
    final contextChanged =
        existing.tenantId.trim() != tenantId ||
        existing.deviceId.trim() != deviceId;

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

    if (suppliedToken.startsWith('odt_')) {
      await _writeDeviceCredential(
        tenantId: publicConfiguration.tenantId,
        deviceId: publicConfiguration.deviceId,
        apiToken: suppliedToken,
      );
      AppSessionManager.instance.clearSession();
      AppSessionManager.instance.setDeviceCredential(
        apiToken: suppliedToken,
        tenantId: publicConfiguration.tenantId,
        deviceId: publicConfiguration.deviceId,
      );
    } else {
      if (contextChanged) {
        AppSessionManager.instance.clearDeviceCredential();
      }
      final credential = await _readDeviceCredential(publicConfiguration);
      if (credential != null) {
        AppSessionManager.instance.setDeviceCredential(
          apiToken: credential.apiToken,
          tenantId: publicConfiguration.tenantId,
          deviceId: publicConfiguration.deviceId,
        );
      }
    }

    if (suppliedToken.isNotEmpty && !suppliedToken.startsWith('odt_')) {
      final sessionManager = AppSessionManager.instance;
      final preservedUser = sessionManager.activeUser;
      final preservedSessionId = sessionManager.sessionId;
      final preservedExpiresAt = sessionManager.expiresAt;
      final preservedIdleTimeout = sessionManager.idleTimeout;
      sessionManager.startSession(
        apiToken: suppliedToken,
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
    await _deleteDeviceCredentialsForDevice(configuration.deviceId);
    AppSessionManager.instance.clearDeviceCredential(
      reason: 'Identité locale du terminal réinitialisée.',
    );
    final deviceId = _generateDeviceId();
    final updated = await saveConfiguration(
      configuration.copyWith(deviceId: deviceId, apiToken: ''),
    );
    return updated.deviceId;
  }

  Future<SyncConfiguration> clearTenantSelection() async {
    final configuration = await loadConfiguration();
    AppSessionManager.instance.clearDeviceCredential();
    return saveConfiguration(
      configuration.copyWith(tenantId: '', enabled: false, apiToken: ''),
    );
  }

  Future<void> clearDeviceAuthorization() async {
    final preferences = await SharedPreferences.getInstance();
    final configuration = await _loadPublicConfiguration(preferences);
    await _deleteDeviceCredential(configuration);
    AppSessionManager.instance.clearDeviceCredential(
      reason: 'Autorisation du terminal supprimée.',
    );
  }

  Future<_StoredDeviceCredential?> _readDeviceCredential(
    SyncConfiguration configuration,
  ) async {
    final credentials = await _readDeviceCredentials();
    for (final credential in credentials) {
      if (credential.matches(configuration)) {
        return credential;
      }
    }
    return null;
  }

  Future<List<_StoredDeviceCredential>> _readDeviceCredentials() async {
    final credentialsByKey = <String, _StoredDeviceCredential>{};
    final rawCollection = await _secureStorage.read(key: _deviceCredentialsKey);
    if (rawCollection != null && rawCollection.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCollection);
        final rawCredentials = decoded is Map ? decoded['credentials'] : null;
        if (rawCredentials is List) {
          for (final rawCredential in rawCredentials) {
            if (rawCredential is! Map) {
              continue;
            }
            final credential = _StoredDeviceCredential.fromJson(
              Map<String, dynamic>.from(rawCredential),
            );
            if (credential.isValid) {
              credentialsByKey[credential.storageKey] = credential;
            }
          }
        }
      } on FormatException {
        // Fail closed: a corrupt collection never exposes a token.
      }
    }

    final legacyRaw = await _secureStorage.read(
      key: _legacyDeviceCredentialKey,
    );
    if (legacyRaw != null && legacyRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(legacyRaw);
        if (decoded is Map) {
          final credential = _StoredDeviceCredential.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (credential.isValid) {
            credentialsByKey[credential.storageKey] = credential;
            await _writeDeviceCredentials(credentialsByKey.values.toList());
          }
        }
      } on FormatException {
        // An invalid legacy token is discarded below.
      }
      await _secureStorage.delete(key: _legacyDeviceCredentialKey);
    }

    return credentialsByKey.values.toList(growable: false);
  }

  Future<void> _writeDeviceCredential({
    required String tenantId,
    required String deviceId,
    required String apiToken,
  }) async {
    final credential = _StoredDeviceCredential(
      tenantId: tenantId.trim(),
      deviceId: deviceId.trim(),
      apiToken: apiToken.trim(),
    );
    if (!credential.isValid) {
      throw ArgumentError('Invalid OpenIRN device credential');
    }
    final credentials = await _readDeviceCredentials();
    final credentialsByKey = <String, _StoredDeviceCredential>{
      for (final stored in credentials) stored.storageKey: stored,
      credential.storageKey: credential,
    };
    await _writeDeviceCredentials(credentialsByKey.values.toList());
  }

  Future<void> _deleteDeviceCredential(SyncConfiguration configuration) async {
    final credentials = await _readDeviceCredentials();
    final remaining = credentials
        .where((credential) => !credential.matches(configuration))
        .toList(growable: false);
    await _writeDeviceCredentials(remaining);
  }

  Future<void> _deleteDeviceCredentialsForDevice(String deviceId) async {
    final normalizedDeviceId = deviceId.trim();
    final credentials = await _readDeviceCredentials();
    final remaining = credentials
        .where((credential) => credential.deviceId != normalizedDeviceId)
        .toList(growable: false);
    await _writeDeviceCredentials(remaining);
  }

  Future<void> _writeDeviceCredentials(
    List<_StoredDeviceCredential> credentials,
  ) async {
    if (credentials.isEmpty) {
      await _secureStorage.delete(key: _deviceCredentialsKey);
      return;
    }
    final sortedCredentials = List<_StoredDeviceCredential>.of(credentials)
      ..sort((left, right) => left.storageKey.compareTo(right.storageKey));
    await _secureStorage.write(
      key: _deviceCredentialsKey,
      value: jsonEncode(<String, dynamic>{
        'schemaVersion': 2,
        'credentials': sortedCredentials
            .map((credential) => credential.toJson())
            .toList(growable: false),
      }),
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

class _StoredDeviceCredential {
  final String tenantId;
  final String deviceId;
  final String apiToken;

  const _StoredDeviceCredential({
    required this.tenantId,
    required this.deviceId,
    required this.apiToken,
  });

  factory _StoredDeviceCredential.fromJson(Map<String, dynamic> json) {
    return _StoredDeviceCredential(
      tenantId: json['tenantId']?.toString().trim() ?? '',
      deviceId: json['deviceId']?.toString().trim() ?? '',
      apiToken: json['apiToken']?.toString().trim() ?? '',
    );
  }

  bool get isValid =>
      tenantId.isNotEmpty && deviceId.isNotEmpty && apiToken.startsWith('odt_');

  String get storageKey => '$tenantId\u0000$deviceId';

  bool matches(SyncConfiguration configuration) =>
      tenantId == configuration.tenantId.trim() &&
      deviceId == configuration.deviceId.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'tenantId': tenantId,
    'deviceId': deviceId,
    'apiToken': apiToken,
  };
}
