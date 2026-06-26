import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/app_user.dart';
import '../../domain/models/sync_configuration.dart';

enum OpenIrnApiReachability {
  ready,
  reachable,
  unreachable,
}

class OpenIrnApiConnectionResult {
  final OpenIrnApiReachability reachability;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiConnectionResult({
    required this.reachability,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    this.responseBody,
  });

  bool get isReachable => reachability != OpenIrnApiReachability.unreachable;
  bool get isReady => reachability == OpenIrnApiReachability.ready;
}

enum OpenIrnApiPushStatus {
  accepted,
  rejected,
  unreachable,
}

class OpenIrnApiPushResult {
  final OpenIrnApiPushStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiPushResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    this.responseBody,
  });

  bool get isAccepted => status == OpenIrnApiPushStatus.accepted;
}

enum OpenIrnApiPullStatus {
  available,
  empty,
  rejected,
  unreachable,
}

class OpenIrnApiPullSnapshot {
  final String serverSyncId;
  final String tenantId;
  final String deviceId;
  final DateTime? receivedAt;
  final String payloadSha256;
  final int campaignCount;
  final Map<String, dynamic>? payload;

  const OpenIrnApiPullSnapshot({
    required this.serverSyncId,
    required this.tenantId,
    required this.deviceId,
    required this.receivedAt,
    required this.payloadSha256,
    required this.campaignCount,
    required this.payload,
  });

  factory OpenIrnApiPullSnapshot.fromJson(Map<String, dynamic> json) {
    final campaignCountValue = json['campaignCount'];
    return OpenIrnApiPullSnapshot(
      serverSyncId: json['serverSyncId']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      receivedAt: DateTime.tryParse(json['receivedAt']?.toString() ?? '')?.toUtc(),
      payloadSha256: json['payloadSha256']?.toString() ?? '',
      campaignCount: campaignCountValue is num ? campaignCountValue.toInt() : 0,
      payload: _jsonObject(json['payload']),
    );
  }

  static Map<String, dynamic>? _jsonObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }
}


enum OpenIrnApiStatusState {
  available,
  rejected,
  unreachable,
}

class OpenIrnApiStatusSnapshot {
  final String serverSyncId;
  final String tenantId;
  final String deviceId;
  final DateTime? receivedAt;
  final String payloadSha256;
  final int campaignCount;

  const OpenIrnApiStatusSnapshot({
    required this.serverSyncId,
    required this.tenantId,
    required this.deviceId,
    required this.receivedAt,
    required this.payloadSha256,
    required this.campaignCount,
  });

  factory OpenIrnApiStatusSnapshot.fromJson(Map<String, dynamic> json) {
    final campaignCountValue = json['campaignCount'];
    return OpenIrnApiStatusSnapshot(
      serverSyncId: json['serverSyncId']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      receivedAt: DateTime.tryParse(json['receivedAt']?.toString() ?? '')?.toUtc(),
      payloadSha256: json['payloadSha256']?.toString() ?? '',
      campaignCount: campaignCountValue is num ? campaignCountValue.toInt() : 0,
    );
  }
}

class OpenIrnApiStatusResult {
  final OpenIrnApiStatusState status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final Map<String, dynamic>? responseBody;
  final String tenantId;
  final DateTime? serverTime;
  final int snapshotCount;
  final int deviceCount;
  final int campaignCount;
  final OpenIrnApiStatusSnapshot? latestSnapshot;

  const OpenIrnApiStatusResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.snapshotCount,
    required this.deviceCount,
    required this.campaignCount,
    this.responseBody,
    this.serverTime,
    this.latestSnapshot,
  });

  bool get isAvailable => status == OpenIrnApiStatusState.available;
}


class OpenIrnSyncEvent {
  final String type;
  final String serverSyncId;
  final String tenantId;
  final String deviceId;
  final DateTime? receivedAt;
  final String payloadSha256;
  final int campaignCount;
  final Map<String, dynamic> raw;

  const OpenIrnSyncEvent({
    required this.type,
    required this.serverSyncId,
    required this.tenantId,
    required this.deviceId,
    required this.receivedAt,
    required this.payloadSha256,
    required this.campaignCount,
    required this.raw,
  });

  factory OpenIrnSyncEvent.fromJson(Map<String, dynamic> json) {
    final rawSnapshot = json['latestSnapshot'];
    final snapshot = rawSnapshot is Map
        ? Map<String, dynamic>.from(rawSnapshot)
        : <String, dynamic>{};
    final campaignCountValue = snapshot['campaignCount'] ?? json['campaignCount'];
    return OpenIrnSyncEvent(
      type: json['type']?.toString() ?? 'openirn.syncEvent',
      serverSyncId: snapshot['serverSyncId']?.toString() ?? json['serverSyncId']?.toString() ?? '',
      tenantId: snapshot['tenantId']?.toString() ?? json['tenantId']?.toString() ?? '',
      deviceId: snapshot['deviceId']?.toString() ?? json['deviceId']?.toString() ?? '',
      receivedAt: DateTime.tryParse(snapshot['receivedAt']?.toString() ?? json['receivedAt']?.toString() ?? '')?.toUtc(),
      payloadSha256: snapshot['payloadSha256']?.toString() ?? json['payloadSha256']?.toString() ?? '',
      campaignCount: campaignCountValue is num ? campaignCountValue.toInt() : int.tryParse(campaignCountValue?.toString() ?? '') ?? 0,
      raw: json,
    );
  }
}


enum OpenIrnApiUsersStatus {
  available,
  empty,
  rejected,
  unreachable,
}

class OpenIrnApiUsersResult {
  final OpenIrnApiUsersStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final List<AppUser> users;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiUsersResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.users,
    this.responseBody,
  });

  bool get hasUsers => users.isNotEmpty;
  bool get isAvailable => status == OpenIrnApiUsersStatus.available;
}

enum OpenIrnApiAuthStatus {
  accepted,
  rejected,
  unreachable,
}

class OpenIrnApiAuthResult {
  final OpenIrnApiAuthStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final String userId;
  final bool mustChangePin;
  final AppUser? user;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiAuthResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.userId,
    required this.mustChangePin,
    this.user,
    this.responseBody,
  });

  bool get isAccepted => status == OpenIrnApiAuthStatus.accepted;
}



enum OpenIrnApiPinUpdateStatus {
  accepted,
  rejected,
  unreachable,
}

class OpenIrnApiPinUpdateResult {
  final OpenIrnApiPinUpdateStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final String userId;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiPinUpdateResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.userId,
    this.responseBody,
  });

  bool get isAccepted => status == OpenIrnApiPinUpdateStatus.accepted;
}

class OpenIrnApiPullResult {
  final OpenIrnApiPullStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final Map<String, dynamic>? responseBody;
  final List<OpenIrnApiPullSnapshot> snapshots;

  const OpenIrnApiPullResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.snapshots,
    this.responseBody,
  });

  bool get hasSnapshots => snapshots.isNotEmpty;
}

class OpenIrnApiClient {
  final Duration timeout;

  const OpenIrnApiClient({this.timeout = const Duration(seconds: 8)});

  Future<OpenIrnApiConnectionResult> testConnection({String? baseUrl}) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final healthUri = Uri.parse('$normalizedBaseUrl/health');

    try {
      final healthResponse = await _get(healthUri);
      final healthStatus = healthResponse.statusCode;
      final decodedBody = _decodeJsonObject(healthResponse.body);

      if (healthStatus >= 200 && healthStatus < 300) {
        return OpenIrnApiConnectionResult(
          reachability: OpenIrnApiReachability.ready,
          url: healthUri.toString(),
          statusCode: healthStatus,
          title: 'API OpenIRN disponible',
          message: 'Le endpoint /health répond correctement.',
          responseBody: decodedBody,
        );
      }

      if (<int>{401, 403}.contains(healthStatus)) {
        return OpenIrnApiConnectionResult(
          reachability: OpenIrnApiReachability.reachable,
          url: healthUri.toString(),
          statusCode: healthStatus,
          title: 'Serveur joignable',
          message: 'Le serveur répond, mais le endpoint /health est protégé. C’est acceptable pour cette étape.',
          responseBody: decodedBody,
        );
      }

      if (healthStatus == 404) {
        final baseResult = await _tryBaseUrl(normalizedBaseUrl);
        if (baseResult.isReachable) {
          return OpenIrnApiConnectionResult(
            reachability: OpenIrnApiReachability.reachable,
            url: healthUri.toString(),
            statusCode: healthStatus,
            title: 'Serveur joignable, endpoint OpenIRN absent',
            message: 'Le serveur répond, mais /health n’existe pas encore. Il faudra l’ajouter côté API serveur.',
            responseBody: decodedBody,
          );
        }
      }

      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.reachable,
        url: healthUri.toString(),
        statusCode: healthStatus,
        title: 'Serveur joignable',
        message: 'Le serveur a répondu avec le statut HTTP $healthStatus. Le endpoint /health devra être normalisé côté API.',
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: healthUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: healthUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: healthUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
      );
    } on FormatException catch (error) {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: healthUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
      );
    } on HttpException catch (error) {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: healthUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
      );
    }
  }

  Future<OpenIrnApiPushResult> pushPayload({
    String? baseUrl,
    required Map<String, dynamic> payload,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final pushUri = Uri.parse('$normalizedBaseUrl/sync/push');

    try {
      final response = await _postJson(
        pushUri,
        payload,
        bearerToken: apiToken,
      );
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final serverSyncId = decodedBody?['serverSyncId']?.toString();
        return OpenIrnApiPushResult(
          status: OpenIrnApiPushStatus.accepted,
          url: pushUri.toString(),
          statusCode: response.statusCode,
          title: 'Synchronisation envoyée',
          message: serverSyncId == null || serverSyncId.isEmpty
              ? 'Le serveur a accepté le payload local.'
              : 'Le serveur a accepté le payload local. Référence serveur : $serverSyncId.',
          responseBody: decodedBody,
        );
      }

      if (<int>{401, 403}.contains(response.statusCode)) {
        return OpenIrnApiPushResult(
          status: OpenIrnApiPushStatus.rejected,
          url: pushUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message: 'Le serveur a refusé le token API. Vérifie le token configuré dans OpenIRN et côté serveur.',
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.rejected,
        url: pushUri.toString(),
        statusCode: response.statusCode,
        title: 'Synchronisation refusée',
        message: 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.unreachable,
        url: pushUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.unreachable,
        url: pushUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.unreachable,
        url: pushUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
      );
    } on FormatException catch (error) {
      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.unreachable,
        url: pushUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
      );
    } on HttpException catch (error) {
      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.unreachable,
        url: pushUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
      );
    }
  }

  Future<OpenIrnApiStatusResult> loadSyncStatus({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final statusUri = Uri.parse('$normalizedBaseUrl/sync/status').replace(
      queryParameters: <String, String>{
        'tenantId': tenantId.trim().isEmpty ? SyncConfiguration.defaultTenantId : tenantId.trim(),
      },
    );

    try {
      final response = await _get(
        statusUri,
        bearerToken: apiToken,
      );
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final latestSnapshot = OpenIrnApiPullSnapshot._jsonObject(decodedBody?['latestSnapshot']);
        final snapshotCount = _intFromJson(decodedBody?['snapshotCount']);
        final deviceCount = _intFromJson(decodedBody?['deviceCount']);
        final campaignCount = _intFromJson(decodedBody?['campaignCount']);
        final tenant = decodedBody?['tenantId']?.toString() ?? tenantId;
        return OpenIrnApiStatusResult(
          status: OpenIrnApiStatusState.available,
          url: statusUri.toString(),
          statusCode: response.statusCode,
          title: 'Statut serveur récupéré',
          message: snapshotCount == 0
              ? 'Le serveur est joignable mais aucun snapshot n’est encore disponible pour ce tenant.'
              : 'Le serveur contient $snapshotCount snapshot(s) pour ce tenant.',
          responseBody: decodedBody,
          tenantId: tenant,
          serverTime: DateTime.tryParse(decodedBody?['serverTime']?.toString() ?? '')?.toUtc(),
          snapshotCount: snapshotCount,
          deviceCount: deviceCount,
          campaignCount: campaignCount,
          latestSnapshot: latestSnapshot == null ? null : OpenIrnApiStatusSnapshot.fromJson(latestSnapshot),
        );
      }

      if (<int>{401, 403}.contains(response.statusCode)) {
        return OpenIrnApiStatusResult(
          status: OpenIrnApiStatusState.rejected,
          url: statusUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message: 'Le serveur a refusé le token API. Vérifie le token configuré dans OpenIRN et côté serveur.',
          responseBody: decodedBody,
          tenantId: tenantId,
          snapshotCount: 0,
          deviceCount: 0,
          campaignCount: 0,
        );
      }

      return OpenIrnApiStatusResult(
        status: OpenIrnApiStatusState.rejected,
        url: statusUri.toString(),
        statusCode: response.statusCode,
        title: 'Statut serveur refusé',
        message: 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        responseBody: decodedBody,
        tenantId: tenantId,
        snapshotCount: 0,
        deviceCount: 0,
        campaignCount: 0,
      );
    } on TimeoutException {
      return OpenIrnApiStatusResult(
        status: OpenIrnApiStatusState.unreachable,
        url: statusUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: tenantId,
        snapshotCount: 0,
        deviceCount: 0,
        campaignCount: 0,
      );
    } on SocketException catch (error) {
      return OpenIrnApiStatusResult(
        status: OpenIrnApiStatusState.unreachable,
        url: statusUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: tenantId,
        snapshotCount: 0,
        deviceCount: 0,
        campaignCount: 0,
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiStatusResult(
        status: OpenIrnApiStatusState.unreachable,
        url: statusUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: tenantId,
        snapshotCount: 0,
        deviceCount: 0,
        campaignCount: 0,
      );
    } on FormatException catch (error) {
      return OpenIrnApiStatusResult(
        status: OpenIrnApiStatusState.unreachable,
        url: statusUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
        tenantId: tenantId,
        snapshotCount: 0,
        deviceCount: 0,
        campaignCount: 0,
      );
    } on HttpException catch (error) {
      return OpenIrnApiStatusResult(
        status: OpenIrnApiStatusState.unreachable,
        url: statusUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: tenantId,
        snapshotCount: 0,
        deviceCount: 0,
        campaignCount: 0,
      );
    }
  }

  Future<OpenIrnApiPullResult> pullSnapshots({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    int limit = 10,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeLimit = limit.clamp(1, 50);
    final pullUri = Uri.parse('$normalizedBaseUrl/sync/pull').replace(
      queryParameters: <String, String>{
        'tenantId': tenantId.trim().isEmpty ? SyncConfiguration.defaultTenantId : tenantId.trim(),
        'limit': safeLimit.toString(),
      },
    );

    try {
      final response = await _get(
        pullUri,
        bearerToken: apiToken,
      );
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawSnapshots = decodedBody?['snapshots'];
        final snapshots = rawSnapshots is List
            ? rawSnapshots
                .whereType<Map>()
                .map((item) => OpenIrnApiPullSnapshot.fromJson(Map<String, dynamic>.from(item)))
                .toList(growable: false)
            : const <OpenIrnApiPullSnapshot>[];
        if (snapshots.isEmpty) {
          return OpenIrnApiPullResult(
            status: OpenIrnApiPullStatus.empty,
            url: pullUri.toString(),
            statusCode: response.statusCode,
            title: 'Aucun snapshot distant',
            message: 'Le serveur est joignable mais ne contient encore aucun snapshot pour ce tenant.',
            responseBody: decodedBody,
            snapshots: snapshots,
          );
        }
        return OpenIrnApiPullResult(
          status: OpenIrnApiPullStatus.available,
          url: pullUri.toString(),
          statusCode: response.statusCode,
          title: 'Snapshots distants récupérés',
          message: '${snapshots.length} snapshot(s) disponible(s) côté serveur.',
          responseBody: decodedBody,
          snapshots: snapshots,
        );
      }

      if (<int>{401, 403}.contains(response.statusCode)) {
        return OpenIrnApiPullResult(
          status: OpenIrnApiPullStatus.rejected,
          url: pullUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message: 'Le serveur a refusé le token API. Vérifie le token configuré dans OpenIRN et côté serveur.',
          responseBody: decodedBody,
          snapshots: const <OpenIrnApiPullSnapshot>[],
        );
      }

      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.rejected,
        url: pullUri.toString(),
        statusCode: response.statusCode,
        title: 'Récupération refusée',
        message: 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        responseBody: decodedBody,
        snapshots: const <OpenIrnApiPullSnapshot>[],
      );
    } on TimeoutException {
      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.unreachable,
        url: pullUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        snapshots: const <OpenIrnApiPullSnapshot>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.unreachable,
        url: pullUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        snapshots: const <OpenIrnApiPullSnapshot>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.unreachable,
        url: pullUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        snapshots: const <OpenIrnApiPullSnapshot>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.unreachable,
        url: pullUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
        snapshots: const <OpenIrnApiPullSnapshot>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.unreachable,
        url: pullUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        snapshots: const <OpenIrnApiPullSnapshot>[],
      );
    }
  }

  Future<OpenIrnApiUsersResult> loadUsers({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty ? SyncConfiguration.defaultTenantId : tenantId.trim();
    final usersUri = Uri.parse('$normalizedBaseUrl/users').replace(
      queryParameters: <String, String>{
        'tenantId': safeTenantId,
      },
    );

    try {
      final response = await _get(
        usersUri,
        bearerToken: apiToken,
      );
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawUsers = decodedBody?['users'];
        final users = rawUsers is List
            ? rawUsers
                .whereType<Map>()
                .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item)))
                .where((user) => user.id.trim().isNotEmpty)
                .toList(growable: false)
            : const <AppUser>[];
        if (users.isEmpty) {
          return OpenIrnApiUsersResult(
            status: OpenIrnApiUsersStatus.empty,
            url: usersUri.toString(),
            statusCode: response.statusCode,
            title: 'Aucun utilisateur central',
            message: 'Le serveur est joignable, mais la base utilisateurs centrale est vide pour ce tenant.',
            tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
            users: users,
            responseBody: decodedBody,
          );
        }
        return OpenIrnApiUsersResult(
          status: OpenIrnApiUsersStatus.available,
          url: usersUri.toString(),
          statusCode: response.statusCode,
          title: 'Utilisateurs centraux récupérés',
          message: '${users.length} utilisateur(s) disponible(s) dans la base centrale.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          users: users,
          responseBody: decodedBody,
        );
      }

      if (<int>{401, 403}.contains(response.statusCode)) {
        return OpenIrnApiUsersResult(
          status: OpenIrnApiUsersStatus.rejected,
          url: usersUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message: 'Le serveur a refusé le token API lors du chargement de la base utilisateurs centrale.',
          tenantId: safeTenantId,
          users: const <AppUser>[],
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.rejected,
        url: usersUri.toString(),
        statusCode: response.statusCode,
        title: 'Base utilisateurs refusée',
        message: 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        users: const <AppUser>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: usersUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: usersUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: usersUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: usersUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: usersUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    }
  }

  Future<OpenIrnApiAuthResult> verifyUserPin({
    String? baseUrl,
    required String tenantId,
    required String userId,
    required String pin,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty ? SyncConfiguration.defaultTenantId : tenantId.trim();
    final safeUserId = userId.trim();
    final authUri = Uri.parse('$normalizedBaseUrl/auth/verify');

    try {
      final response = await _postJson(
        authUri,
        <String, dynamic>{
          'tenantId': safeTenantId,
          'userId': safeUserId,
          'pin': pin,
        },
        bearerToken: apiToken,
      );
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawUser = decodedBody?['user'];
        final user = rawUser is Map ? AppUser.fromJson(Map<String, dynamic>.from(rawUser)) : null;
        final mustChangePin = decodedBody?['mustChangePin'] == true;
        return OpenIrnApiAuthResult(
          status: OpenIrnApiAuthStatus.accepted,
          url: authUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification acceptée',
          message: mustChangePin
              ? 'Authentification acceptée. Le code initial doit être remplacé côté administration.'
              : 'Authentification acceptée.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          userId: decodedBody?['userId']?.toString() ?? safeUserId,
          mustChangePin: mustChangePin,
          user: user,
          responseBody: decodedBody,
        );
      }

      if (<int>{401, 403, 404}.contains(response.statusCode)) {
        return OpenIrnApiAuthResult(
          status: OpenIrnApiAuthStatus.rejected,
          url: authUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message: decodedBody?['detail']?.toString() ?? 'Le code utilisateur est incorrect ou l’utilisateur est inactif.',
          tenantId: safeTenantId,
          userId: safeUserId,
          mustChangePin: false,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiAuthResult(
        status: OpenIrnApiAuthStatus.rejected,
        url: authUri.toString(),
        statusCode: response.statusCode,
        title: 'Authentification refusée',
        message: 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        userId: safeUserId,
        mustChangePin: false,
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiAuthResult(
        status: OpenIrnApiAuthStatus.unreachable,
        url: authUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        userId: safeUserId,
        mustChangePin: false,
      );
    } on SocketException catch (error) {
      return OpenIrnApiAuthResult(
        status: OpenIrnApiAuthStatus.unreachable,
        url: authUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
        mustChangePin: false,
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiAuthResult(
        status: OpenIrnApiAuthStatus.unreachable,
        url: authUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
        mustChangePin: false,
      );
    } on FormatException catch (error) {
      return OpenIrnApiAuthResult(
        status: OpenIrnApiAuthStatus.unreachable,
        url: authUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
        mustChangePin: false,
      );
    } on HttpException catch (error) {
      return OpenIrnApiAuthResult(
        status: OpenIrnApiAuthStatus.unreachable,
        url: authUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
        mustChangePin: false,
      );
    }
  }



  Future<OpenIrnApiPinUpdateResult> updateUserPin({
    String? baseUrl,
    required String tenantId,
    required String userId,
    required String pin,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty ? SyncConfiguration.defaultTenantId : tenantId.trim();
    final safeUserId = userId.trim();
    final pinUri = Uri.parse('$normalizedBaseUrl/users/pin');

    try {
      final response = await _postJson(
        pinUri,
        <String, dynamic>{
          'tenantId': safeTenantId,
          'userId': safeUserId,
          'pin': pin,
        },
        bearerToken: apiToken,
      );
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiPinUpdateResult(
          status: OpenIrnApiPinUpdateStatus.accepted,
          url: pinUri.toString(),
          statusCode: response.statusCode,
          title: 'Code utilisateur mis à jour',
          message: 'Le code personnel a été remplacé côté serveur.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          userId: decodedBody?['userId']?.toString() ?? safeUserId,
          responseBody: decodedBody,
        );
      }

      if (<int>{400, 401, 403, 404}.contains(response.statusCode)) {
        return OpenIrnApiPinUpdateResult(
          status: OpenIrnApiPinUpdateStatus.rejected,
          url: pinUri.toString(),
          statusCode: response.statusCode,
          title: 'Modification refusée',
          message: decodedBody?['detail']?.toString() ?? 'Le serveur a refusé la modification du code.',
          tenantId: safeTenantId,
          userId: safeUserId,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiPinUpdateResult(
        status: OpenIrnApiPinUpdateStatus.rejected,
        url: pinUri.toString(),
        statusCode: response.statusCode,
        title: 'Modification refusée',
        message: 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        userId: safeUserId,
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiPinUpdateResult(
        status: OpenIrnApiPinUpdateStatus.unreachable,
        url: pinUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        userId: safeUserId,
      );
    } on SocketException catch (error) {
      return OpenIrnApiPinUpdateResult(
        status: OpenIrnApiPinUpdateStatus.unreachable,
        url: pinUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiPinUpdateResult(
        status: OpenIrnApiPinUpdateStatus.unreachable,
        url: pinUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
      );
    } on FormatException catch (error) {
      return OpenIrnApiPinUpdateResult(
        status: OpenIrnApiPinUpdateStatus.unreachable,
        url: pinUri.toString(),
        statusCode: null,
        title: 'URL API invalide',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
      );
    } on HttpException catch (error) {
      return OpenIrnApiPinUpdateResult(
        status: OpenIrnApiPinUpdateStatus.unreachable,
        url: pinUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        userId: safeUserId,
      );
    }
  }

  Stream<OpenIrnSyncEvent> watchSyncEvents({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    String? sinceServerSyncId,
    Duration reconnectDelay = const Duration(seconds: 5),
  }) async* {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final queryParameters = <String, String>{
      'tenantId': tenantId.trim().isEmpty ? SyncConfiguration.defaultTenantId : tenantId.trim(),
    };
    final since = sinceServerSyncId?.trim();
    if (since != null && since.isNotEmpty) {
      queryParameters['since'] = since;
    }
    final eventsUri = Uri.parse('$normalizedBaseUrl/sync/events').replace(
      queryParameters: queryParameters,
    );

    while (true) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(eventsUri).timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
        final trimmedToken = apiToken.trim();
        if (trimmedToken.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $trimmedToken');
        }

        final response = await request.close().timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('SSE refused with HTTP ${response.statusCode}');
        }

        final dataLines = <String>[];
        await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.trim().isEmpty) {
            final rawData = dataLines.join('\n').trim();
            dataLines.clear();
            if (rawData.isEmpty) {
              continue;
            }
            final decoded = jsonDecode(rawData);
            if (decoded is Map) {
              final payload = Map<String, dynamic>.from(decoded);
              final event = OpenIrnSyncEvent.fromJson(payload);
              if (event.serverSyncId.trim().isNotEmpty) {
                yield event;
              }
            }
            continue;
          }
          if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
          }
        }
      } on FormatException {
        // Ignore malformed event and reconnect.
      } on TimeoutException {
        // Reconnect below.
      } on SocketException {
        // Reconnect below.
      } on HttpException {
        // Reconnect below.
      } on HandshakeException {
        // Reconnect below.
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(reconnectDelay);
    }
  }

  Future<OpenIrnApiConnectionResult> _tryBaseUrl(String normalizedBaseUrl) async {
    final baseUri = Uri.parse(normalizedBaseUrl);
    try {
      final response = await _get(baseUri);
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.reachable,
        url: baseUri.toString(),
        statusCode: response.statusCode,
        title: 'Serveur joignable',
        message: 'Le serveur a répondu sur l’URL API de base avec le statut HTTP ${response.statusCode}.',
        responseBody: _decodeJsonObject(response.body),
      );
    } catch (_) {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: baseUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: 'Impossible de joindre l’URL API de base.',
      );
    }
  }

  Future<_HttpResponse> _get(
    Uri uri, {
    String bearerToken = '',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      final trimmedToken = bearerToken.trim();
      if (trimmedToken.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $trimmedToken');
      }
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      return _HttpResponse(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  Future<_HttpResponse> _postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    String bearerToken = '',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      final trimmedToken = bearerToken.trim();
      if (trimmedToken.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $trimmedToken');
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      return _HttpResponse(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  int _intFromJson(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class _HttpResponse {
  final int statusCode;
  final String body;

  const _HttpResponse({required this.statusCode, required this.body});
}
