import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/api_session.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/authorized_device.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/official_referential.dart';
import '../../domain/models/security_audit_event.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/models/tenant_info.dart';
import '../../domain/services/app_session_manager.dart';

enum OpenIrnApiReachability { ready, reachable, unreachable }

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

enum OpenIrnApiPushStatus { accepted, rejected, unreachable }

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

enum OpenIrnApiPullStatus { available, empty, rejected, unreachable }

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
      receivedAt: DateTime.tryParse(
        json['receivedAt']?.toString() ?? '',
      )?.toUtc(),
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

enum OpenIrnApiStatusState { available, rejected, unreachable }

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
      receivedAt: DateTime.tryParse(
        json['receivedAt']?.toString() ?? '',
      )?.toUtc(),
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
    final campaignCountValue =
        snapshot['campaignCount'] ?? json['campaignCount'];
    return OpenIrnSyncEvent(
      type: json['type']?.toString() ?? 'openirn.syncEvent',
      serverSyncId:
          snapshot['serverSyncId']?.toString() ??
          json['serverSyncId']?.toString() ??
          '',
      tenantId:
          snapshot['tenantId']?.toString() ??
          json['tenantId']?.toString() ??
          '',
      deviceId:
          snapshot['deviceId']?.toString() ??
          json['deviceId']?.toString() ??
          '',
      receivedAt: DateTime.tryParse(
        snapshot['receivedAt']?.toString() ??
            json['receivedAt']?.toString() ??
            '',
      )?.toUtc(),
      payloadSha256:
          snapshot['payloadSha256']?.toString() ??
          json['payloadSha256']?.toString() ??
          '',
      campaignCount: campaignCountValue is num
          ? campaignCountValue.toInt()
          : int.tryParse(campaignCountValue?.toString() ?? '') ?? 0,
      raw: json,
    );
  }
}

enum OpenIrnApiCurrentReferentialStatus { available, rejected, unreachable }

class OpenIrnApiCurrentReferentialResult {
  final OpenIrnApiCurrentReferentialStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final IrnReferential? referential;
  final OfficialReferentialSummary? summary;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiCurrentReferentialResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    this.referential,
    this.summary,
    this.responseBody,
  });

  bool get isAvailable =>
      status == OpenIrnApiCurrentReferentialStatus.available;
}

enum OpenIrnApiDevicesStatus { available, rejected, unreachable }

class OpenIrnApiSessionsResult {
  final OpenIrnApiDevicesStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final List<ApiSessionInfo> sessions;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiSessionsResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.sessions,
    this.responseBody,
  });

  bool get isAvailable => status == OpenIrnApiDevicesStatus.available;
}

class OpenIrnApiSecurityAuditResult {
  final OpenIrnApiDevicesStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final List<SecurityAuditEvent> events;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiSecurityAuditResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.events,
    this.responseBody,
  });

  bool get isAvailable => status == OpenIrnApiDevicesStatus.available;
}

class OpenIrnApiDevicesResult {
  final OpenIrnApiDevicesStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final List<AuthorizedDevice> devices;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiDevicesResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.devices,
    this.responseBody,
  });

  bool get isAvailable => status == OpenIrnApiDevicesStatus.available;
}

enum OpenIrnApiEnrollmentStatus { accepted, rejected, unreachable }

class OpenIrnApiEnrollmentResult {
  final OpenIrnApiEnrollmentStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final String enrollmentId;
  final String code;
  final DateTime? expiresAt;
  final int expiresInMinutes;
  final String qrPayloadText;
  final AuthorizedDevice? device;
  final String apiToken;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiEnrollmentResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.enrollmentId,
    required this.code,
    required this.expiresAt,
    required this.expiresInMinutes,
    required this.qrPayloadText,
    required this.apiToken,
    this.device,
    this.responseBody,
  });

  bool get isAccepted => status == OpenIrnApiEnrollmentStatus.accepted;
}

enum OpenIrnApiUsersStatus { available, empty, rejected, unreachable }

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

enum OpenIrnApiAuthStatus { accepted, rejected, unreachable }

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

enum OpenIrnApiPinUpdateStatus { accepted, rejected, unreachable }

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

enum OpenIrnApiTenantsStatus { available, rejected, unreachable }

class OpenIrnApiTenantsResult {
  final OpenIrnApiTenantsStatus status;
  final String url;
  final int? statusCode;
  final String title;
  final String message;
  final String tenantId;
  final String defaultTenantId;
  final bool solutionAdministrator;
  final List<TenantInfo> tenants;
  final Map<String, dynamic>? responseBody;

  const OpenIrnApiTenantsResult({
    required this.status,
    required this.url,
    required this.statusCode,
    required this.title,
    required this.message,
    required this.tenantId,
    required this.defaultTenantId,
    this.solutionAdministrator = false,
    required this.tenants,
    this.responseBody,
  });

  bool get isAvailable => status == OpenIrnApiTenantsStatus.available;
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
          title: 'Serveur OpenIRN disponible',
          message: 'Le serveur OpenIRN répond correctement.',
          responseBody: decodedBody,
        );
      }

      if (<int>{401, 403}.contains(healthStatus)) {
        return OpenIrnApiConnectionResult(
          reachability: OpenIrnApiReachability.reachable,
          url: healthUri.toString(),
          statusCode: healthStatus,
          title: 'Serveur joignable',
          message:
              'Le serveur répond. Certains contrôles techniques sont protégés, ce qui est normal.',
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
            title: 'Serveur joignable, contrôle OpenIRN absent',
            message:
                'Le serveur répond, mais le contrôle de disponibilité OpenIRN n’est pas encore configuré.',
            responseBody: decodedBody,
          );
        }
      }

      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.reachable,
        url: healthUri.toString(),
        statusCode: healthStatus,
        title: 'Serveur joignable',
        message:
            'Le serveur a répondu avec le statut HTTP $healthStatus. Le contrôle de disponibilité devra être harmonisé.',
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
        title: 'Adresse serveur invalide',
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

  Future<OpenIrnApiTenantsResult> loadTenants({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final uri = Uri.parse(
      '$normalizedBaseUrl/tenants',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _get(uri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);
      final rawTenants = decodedBody?['tenants'];
      final tenants = rawTenants is List
          ? rawTenants
                .whereType<Map>()
                .map(
                  (item) =>
                      TenantInfo.fromJson(Map<String, dynamic>.from(item)),
                )
                .where((tenant) => tenant.id.trim().isNotEmpty)
                .toList(growable: false)
          : const <TenantInfo>[];

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiTenantsResult(
          status: OpenIrnApiTenantsStatus.available,
          url: uri.toString(),
          statusCode: response.statusCode,
          title: 'Espaces de travail récupérés',
          message: '${tenants.length} espace(s) de travail disponible(s).',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          defaultTenantId:
              decodedBody?['defaultTenantId']?.toString() ?? 'default',
          solutionAdministrator: decodedBody?['solutionAdministrator'] == true,
          tenants: tenants,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.rejected,
        url: uri.toString(),
        statusCode: response.statusCode,
        title: 'Espaces de travail refusés',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    }
  }

  Future<OpenIrnApiTenantsResult> createTenant({
    String? baseUrl,
    required String requesterTenantId,
    required String tenantId,
    required String displayName,
    required String description,
    required String pilotFirstName,
    required String pilotLastName,
    required String pilotEmail,
    required String pilotPin,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeRequesterTenantId = requesterTenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : requesterTenantId.trim();
    final uri = Uri.parse('$normalizedBaseUrl/tenants');

    try {
      final response = await _postJson(uri, <String, dynamic>{
        'requesterTenantId': safeRequesterTenantId,
        'tenantId': tenantId.trim(),
        'displayName': displayName.trim(),
        'description': description.trim(),
        'pilot': <String, dynamic>{
          'firstName': pilotFirstName.trim(),
          'lastName': pilotLastName.trim(),
          'email': pilotEmail.trim().toLowerCase(),
          'pin': pilotPin.trim(),
        },
      }, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);
      final rawTenants = decodedBody?['tenants'];
      final tenants = rawTenants is List
          ? rawTenants
                .whereType<Map>()
                .map(
                  (item) =>
                      TenantInfo.fromJson(Map<String, dynamic>.from(item)),
                )
                .where((tenant) => tenant.id.trim().isNotEmpty)
                .toList(growable: false)
          : const <TenantInfo>[];

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiTenantsResult(
          status: OpenIrnApiTenantsStatus.available,
          url: uri.toString(),
          statusCode: response.statusCode,
          title: 'Espace de travail créé',
          message:
              decodedBody?['message']?.toString() ??
              'Espace de travail créé avec un Pilote IRN initial.',
          tenantId: decodedBody?['tenantId']?.toString() ?? tenantId.trim(),
          defaultTenantId:
              decodedBody?['defaultTenantId']?.toString() ?? 'default',
          solutionAdministrator: decodedBody?['solutionAdministrator'] == true,
          tenants: tenants,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.rejected,
        url: uri.toString(),
        statusCode: response.statusCode,
        title: 'Création refusée',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: tenantId.trim(),
        defaultTenantId: 'default',
        tenants: tenants,
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: tenantId.trim(),
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: tenantId.trim(),
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: tenantId.trim(),
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: tenantId.trim(),
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiTenantsResult(
        status: OpenIrnApiTenantsStatus.unreachable,
        url: uri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: tenantId.trim(),
        defaultTenantId: 'default',
        tenants: const <TenantInfo>[],
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
      final response = await _postJson(pushUri, payload, bearerToken: apiToken);
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
          message:
              'Le serveur a refusé la clé d’accès. Veuillez vérifier la configuration OpenIRN et serveur.',
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiPushResult(
        status: OpenIrnApiPushStatus.rejected,
        url: pushUri.toString(),
        statusCode: response.statusCode,
        title: 'Synchronisation refusée',
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
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
        title: 'Adresse serveur invalide',
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
        'tenantId': tenantId.trim().isEmpty
            ? SyncConfiguration.defaultTenantId
            : tenantId.trim(),
      },
    );

    try {
      final response = await _get(statusUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final latestSnapshot = OpenIrnApiPullSnapshot._jsonObject(
          decodedBody?['latestSnapshot'],
        );
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
              ? 'Le serveur est joignable mais aucune sauvegarde de synchronisation n’est encore disponible pour cet espace.'
              : 'Le serveur contient $snapshotCount sauvegarde(s) de synchronisation pour cet espace.',
          responseBody: decodedBody,
          tenantId: tenant,
          serverTime: DateTime.tryParse(
            decodedBody?['serverTime']?.toString() ?? '',
          )?.toUtc(),
          snapshotCount: snapshotCount,
          deviceCount: deviceCount,
          campaignCount: campaignCount,
          latestSnapshot: latestSnapshot == null
              ? null
              : OpenIrnApiStatusSnapshot.fromJson(latestSnapshot),
        );
      }

      if (<int>{401, 403}.contains(response.statusCode)) {
        return OpenIrnApiStatusResult(
          status: OpenIrnApiStatusState.rejected,
          url: statusUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message:
              'Le serveur a refusé la clé d’accès. Veuillez vérifier la configuration OpenIRN et serveur.',
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
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
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
        title: 'Adresse serveur invalide',
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
        'tenantId': tenantId.trim().isEmpty
            ? SyncConfiguration.defaultTenantId
            : tenantId.trim(),
        'limit': safeLimit.toString(),
      },
    );

    try {
      final response = await _get(pullUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawSnapshots = decodedBody?['snapshots'];
        final snapshots = rawSnapshots is List
            ? rawSnapshots
                  .whereType<Map>()
                  .map(
                    (item) => OpenIrnApiPullSnapshot.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .toList(growable: false)
            : const <OpenIrnApiPullSnapshot>[];
        if (snapshots.isEmpty) {
          return OpenIrnApiPullResult(
            status: OpenIrnApiPullStatus.empty,
            url: pullUri.toString(),
            statusCode: response.statusCode,
            title: 'Aucune sauvegarde de synchronisation distante',
            message:
                'Le serveur est joignable mais ne contient encore aucune sauvegarde de synchronisation pour cet espace.',
            responseBody: decodedBody,
            snapshots: snapshots,
          );
        }
        return OpenIrnApiPullResult(
          status: OpenIrnApiPullStatus.available,
          url: pullUri.toString(),
          statusCode: response.statusCode,
          title: 'Sauvegardes de synchronisation récupérées',
          message:
              '${snapshots.length} sauvegarde(s) de synchronisation disponible(s) côté serveur.',
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
          message:
              'Le serveur a refusé la clé d’accès. Veuillez vérifier la configuration OpenIRN et serveur.',
          responseBody: decodedBody,
          snapshots: const <OpenIrnApiPullSnapshot>[],
        );
      }

      return OpenIrnApiPullResult(
        status: OpenIrnApiPullStatus.rejected,
        url: pullUri.toString(),
        statusCode: response.statusCode,
        title: 'Récupération refusée',
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
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
        title: 'Adresse serveur invalide',
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
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final usersUri = Uri.parse(
      '$normalizedBaseUrl/users',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _get(usersUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawUsers = decodedBody?['users'];
        final users = rawUsers is List
            ? rawUsers
                  .whereType<Map>()
                  .map(
                    (item) => AppUser.fromJson(Map<String, dynamic>.from(item)),
                  )
                  .where((user) => user.id.trim().isNotEmpty)
                  .toList(growable: false)
            : const <AppUser>[];
        if (users.isEmpty) {
          return OpenIrnApiUsersResult(
            status: OpenIrnApiUsersStatus.empty,
            url: usersUri.toString(),
            statusCode: response.statusCode,
            title: 'Aucun utilisateur disponible',
            message:
                'Le serveur est joignable, mais aucun utilisateur n’est disponible dans cet espace de travail.',
            tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
            users: users,
            responseBody: decodedBody,
          );
        }
        return OpenIrnApiUsersResult(
          status: OpenIrnApiUsersStatus.available,
          url: usersUri.toString(),
          statusCode: response.statusCode,
          title: 'Utilisateurs récupérés',
          message: '${users.length} utilisateur(s) disponible(s).',
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
          message:
              'Le serveur a refusé la clé d’accès lors du chargement des utilisateurs.',
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
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
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
        title: 'Adresse serveur invalide',
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

  List<AppUser> _sortUsers(List<AppUser> users) {
    final sorted = users.toList();
    sorted.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return sorted;
  }

  Future<OpenIrnApiUsersResult> replaceUsers({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required List<AppUser> users,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final replaceUri = Uri.parse('$normalizedBaseUrl/users/replace');
    final usersToSave = _sortUsers(users);

    try {
      final response = await _postJson(replaceUri, <String, dynamic>{
        'tenantId': safeTenantId,
        'users': usersToSave.map((user) => user.toJson()).toList(),
      }, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiUsersResult(
          status: usersToSave.isEmpty
              ? OpenIrnApiUsersStatus.empty
              : OpenIrnApiUsersStatus.available,
          url: replaceUri.toString(),
          statusCode: response.statusCode,
          title: 'Utilisateurs centraux mis à jour',
          message:
              '${usersToSave.length} utilisateur(s) synchronisé(s) immédiatement avec le serveur.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          users: usersToSave,
          responseBody: decodedBody,
        );
      }

      if (<int>{400, 401, 403}.contains(response.statusCode)) {
        return OpenIrnApiUsersResult(
          status: OpenIrnApiUsersStatus.rejected,
          url: replaceUri.toString(),
          statusCode: response.statusCode,
          title: 'Modification refusée',
          message:
              decodedBody?['detail']?.toString() ??
              'Le serveur a refusé la mise à jour de la base utilisateurs centrale.',
          tenantId: safeTenantId,
          users: const <AppUser>[],
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.rejected,
        url: replaceUri.toString(),
        statusCode: response.statusCode,
        title: 'Modification refusée',
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        users: const <AppUser>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: replaceUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: replaceUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: replaceUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: replaceUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        users: const <AppUser>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiUsersResult(
        status: OpenIrnApiUsersStatus.unreachable,
        url: replaceUri.toString(),
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
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final safeUserId = userId.trim();
    final authUri = Uri.parse('$normalizedBaseUrl/auth/verify');

    try {
      final response = await _postJson(authUri, <String, dynamic>{
        'tenantId': safeTenantId,
        'deviceId': AppSessionManager.instance.deviceId,
        'userId': safeUserId,
        'pin': pin,
      }, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawUser = decodedBody?['user'];
        final user = rawUser is Map
            ? AppUser.fromJson(Map<String, dynamic>.from(rawUser))
            : null;
        final mustChangePin = decodedBody?['mustChangePin'] == true;
        final sessionToken = decodedBody?['apiToken']?.toString().trim() ?? '';
        final sessionExpiresAt = DateTime.tryParse(
          decodedBody?['expiresAt']?.toString() ?? '',
        )?.toUtc();
        final idleTimeoutMinutes = int.tryParse(
          decodedBody?['idleTimeoutMinutes']?.toString() ?? '',
        );
        final sessionId = decodedBody?['sessionId']?.toString().trim() ?? '';
        if (sessionToken.isNotEmpty) {
          AppSessionManager.instance.startSession(
            apiToken: sessionToken,
            tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
            deviceId: AppSessionManager.instance.deviceId,
            sessionId: sessionId,
            expiresAt: sessionExpiresAt,
            idleTimeout: idleTimeoutMinutes == null || idleTimeoutMinutes <= 0
                ? null
                : Duration(minutes: idleTimeoutMinutes),
            activeUser: user,
          );
        }
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
          message:
              decodedBody?['detail']?.toString() ??
              'Le code utilisateur est incorrect ou l’utilisateur est inactif.',
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
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
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
        title: 'Adresse serveur invalide',
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
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final safeUserId = userId.trim();
    final pinUri = Uri.parse('$normalizedBaseUrl/users/pin');

    try {
      final response = await _postJson(pinUri, <String, dynamic>{
        'tenantId': safeTenantId,
        'userId': safeUserId,
        'pin': pin,
      }, bearerToken: apiToken);
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
          message:
              decodedBody?['detail']?.toString() ??
              'Le serveur a refusé la modification du code.',
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
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
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
        title: 'Adresse serveur invalide',
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

  Future<OpenIrnApiSessionsResult> loadApiSessions({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    bool includeInactive = true,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final sessionsUri = Uri.parse('$normalizedBaseUrl/auth/sessions').replace(
      queryParameters: <String, String>{
        'tenantId': safeTenantId,
        'includeInactive': includeInactive ? 'true' : 'false',
      },
    );

    try {
      final response = await _get(sessionsUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawSessions = decodedBody?['sessions'];
        final sessions = rawSessions is List
            ? rawSessions
                  .whereType<Map>()
                  .map(
                    (item) => ApiSessionInfo.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .where((session) => session.sessionId.trim().isNotEmpty)
                  .toList(growable: false)
            : const <ApiSessionInfo>[];
        return OpenIrnApiSessionsResult(
          status: OpenIrnApiDevicesStatus.available,
          url: sessionsUri.toString(),
          statusCode: response.statusCode,
          title: 'Sessions récupérées',
          message: '${sessions.length} session(s) serveur récupérée(s).',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          sessions: sessions,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.rejected,
        url: sessionsUri.toString(),
        statusCode: response.statusCode,
        title: response.statusCode == 401 || response.statusCode == 403
            ? 'Authentification refusée'
            : 'Sessions refusées',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: sessionsUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: sessionsUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: sessionsUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: sessionsUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: sessionsUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    }
  }

  Future<OpenIrnApiSecurityAuditResult> loadSecurityAuditEvents({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    int limit = 100,
    bool includeAuthAttempts = true,
    bool includeDeviceAudit = true,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final auditUri = Uri.parse('$normalizedBaseUrl/security/audit').replace(
      queryParameters: <String, String>{
        'tenantId': safeTenantId,
        'limit': limit.clamp(25, 500).toString(),
        'includeAuthAttempts': includeAuthAttempts ? 'true' : 'false',
        'includeDeviceAudit': includeDeviceAudit ? 'true' : 'false',
      },
    );

    try {
      final response = await _get(auditUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawEvents = decodedBody?['events'];
        final events = rawEvents is List
            ? rawEvents
                  .whereType<Map>()
                  .map(
                    (item) => SecurityAuditEvent.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .toList(growable: false)
            : const <SecurityAuditEvent>[];
        return OpenIrnApiSecurityAuditResult(
          status: OpenIrnApiDevicesStatus.available,
          url: auditUri.toString(),
          statusCode: response.statusCode,
          title: 'Journal sécurité récupéré',
          message: '${events.length} événement(s) sécurité récupéré(s).',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          events: events,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiSecurityAuditResult(
        status: OpenIrnApiDevicesStatus.rejected,
        url: auditUri.toString(),
        statusCode: response.statusCode,
        title: response.statusCode == 401 || response.statusCode == 403
            ? 'Authentification refusée'
            : 'Journal sécurité refusé',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        events: const <SecurityAuditEvent>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiSecurityAuditResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: auditUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        events: const <SecurityAuditEvent>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiSecurityAuditResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: auditUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        events: const <SecurityAuditEvent>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiSecurityAuditResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: auditUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        events: const <SecurityAuditEvent>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiSecurityAuditResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: auditUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        events: const <SecurityAuditEvent>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiSecurityAuditResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: auditUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        events: const <SecurityAuditEvent>[],
      );
    }
  }

  Future<OpenIrnApiSessionsResult> revokeCurrentApiSession({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final revokeUri = Uri.parse(
      '$normalizedBaseUrl/auth/session/current',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _delete(revokeUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiSessionsResult(
          status: OpenIrnApiDevicesStatus.available,
          url: revokeUri.toString(),
          statusCode: response.statusCode,
          title: 'Session verrouillée',
          message:
              decodedBody?['message']?.toString() ?? 'Session verrouillée.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          sessions: const <ApiSessionInfo>[],
          responseBody: decodedBody,
        );
      }
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.rejected,
        url: revokeUri.toString(),
        statusCode: response.statusCode,
        title: 'Verrouillage serveur refusé',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    }
  }

  Future<OpenIrnApiSessionsResult> revokeApiSession({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required String sessionId,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final revokeUri = Uri.parse(
      '$normalizedBaseUrl/auth/sessions/$sessionId',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _delete(revokeUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiSessionsResult(
          status: OpenIrnApiDevicesStatus.available,
          url: revokeUri.toString(),
          statusCode: response.statusCode,
          title: 'Session révoquée',
          message: decodedBody?['message']?.toString() ?? 'Session révoquée.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          sessions: const <ApiSessionInfo>[],
          responseBody: decodedBody,
        );
      }
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.rejected,
        url: revokeUri.toString(),
        statusCode: response.statusCode,
        title: 'Révocation refusée',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiSessionsResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: revokeUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        sessions: const <ApiSessionInfo>[],
      );
    }
  }

  Future<OpenIrnApiDevicesResult> loadDevices({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final devicesUri = Uri.parse(
      '$normalizedBaseUrl/devices',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _get(devicesUri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawDevices = decodedBody?['devices'];
        final devices = rawDevices is List
            ? rawDevices
                  .whereType<Map>()
                  .map(
                    (item) => AuthorizedDevice.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .where((device) => device.deviceId.trim().isNotEmpty)
                  .toList(growable: false)
            : const <AuthorizedDevice>[];
        return OpenIrnApiDevicesResult(
          status: OpenIrnApiDevicesStatus.available,
          url: devicesUri.toString(),
          statusCode: response.statusCode,
          title: 'Terminaux récupérés',
          message: '${devices.length} terminal(aux) autorisé(s) côté serveur.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          devices: devices,
          responseBody: decodedBody,
        );
      }

      if (<int>{401, 403}.contains(response.statusCode)) {
        return OpenIrnApiDevicesResult(
          status: OpenIrnApiDevicesStatus.rejected,
          url: devicesUri.toString(),
          statusCode: response.statusCode,
          title: 'Authentification refusée',
          message:
              'Le serveur a refusé la clé d’accès lors du chargement des terminaux autorisés.',
          tenantId: safeTenantId,
          devices: const <AuthorizedDevice>[],
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.rejected,
        url: devicesUri.toString(),
        statusCode: response.statusCode,
        title: 'Terminaux refusés',
        message:
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        devices: const <AuthorizedDevice>[],
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: devicesUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        devices: const <AuthorizedDevice>[],
      );
    } on SocketException catch (error) {
      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: devicesUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        devices: const <AuthorizedDevice>[],
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: devicesUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        devices: const <AuthorizedDevice>[],
      );
    } on FormatException catch (error) {
      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: devicesUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        devices: const <AuthorizedDevice>[],
      );
    } on HttpException catch (error) {
      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.unreachable,
        url: devicesUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        devices: const <AuthorizedDevice>[],
      );
    }
  }

  Future<OpenIrnApiEnrollmentResult> createDeviceEnrollment({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required String createdByUserId,
    String label = '',
    int expiresInMinutes = 10,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final enrollmentUri = Uri.parse('$normalizedBaseUrl/devices/enrollment');

    try {
      final response = await _postJson(enrollmentUri, <String, dynamic>{
        'tenantId': safeTenantId,
        'createdByUserId': createdByUserId.trim(),
        'label': label.trim(),
        'expiresInMinutes': expiresInMinutes.clamp(1, 60),
      }, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiEnrollmentResult(
          status: OpenIrnApiEnrollmentStatus.accepted,
          url: enrollmentUri.toString(),
          statusCode: response.statusCode,
          title: 'Invitation créée',
          message: 'Le code d’appairage est prêt. Il est à usage unique.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          enrollmentId: decodedBody?['enrollmentId']?.toString() ?? '',
          code: decodedBody?['code']?.toString() ?? '',
          expiresAt: DateTime.tryParse(
            decodedBody?['expiresAt']?.toString() ?? '',
          )?.toUtc(),
          expiresInMinutes: _intFromJson(decodedBody?['expiresInMinutes']),
          qrPayloadText: decodedBody?['qrPayloadText']?.toString() ?? '',
          apiToken: '',
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.rejected,
        url: enrollmentUri.toString(),
        statusCode: response.statusCode,
        title: 'Invitation refusée',
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: enrollmentUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on SocketException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: enrollmentUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: enrollmentUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on FormatException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: enrollmentUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on HttpException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: enrollmentUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    }
  }

  Future<OpenIrnApiEnrollmentResult> consumeDeviceEnrollment({
    String? baseUrl,
    required String tenantId,
    required String code,
    required String deviceName,
    required String platform,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final consumeUri = Uri.parse(
      '$normalizedBaseUrl/devices/enrollment/consume',
    );

    try {
      final response = await _postJson(consumeUri, <String, dynamic>{
        'tenantId': safeTenantId,
        'code': code.trim(),
        'deviceName': deviceName.trim(),
        'platform': platform.trim(),
      });
      final decodedBody = _decodeJsonObject(response.body);
      final rawDevice = decodedBody?['device'];
      final device = rawDevice is Map
          ? AuthorizedDevice.fromJson(Map<String, dynamic>.from(rawDevice))
          : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return OpenIrnApiEnrollmentResult(
          status: OpenIrnApiEnrollmentStatus.accepted,
          url: consumeUri.toString(),
          statusCode: response.statusCode,
          title: 'Terminal autorisé',
          message:
              'Ce terminal est autorisé. Aucune clé sensible n’est stockée localement.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          enrollmentId: device?.enrollmentId ?? '',
          code: '',
          expiresAt: null,
          expiresInMinutes: 0,
          qrPayloadText: '',
          apiToken: '',
          device: device,
          responseBody: decodedBody,
        );
      }

      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.rejected,
        url: consumeUri.toString(),
        statusCode: response.statusCode,
        title: _enrollmentConsumeErrorTitle(response.statusCode),
        message:
            decodedBody?['detail']?.toString() ??
            'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
        device: device,
        responseBody: decodedBody,
      );
    } on TimeoutException {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: consumeUri.toString(),
        statusCode: null,
        title: 'Délai dépassé',
        message: 'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on SocketException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: consumeUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on HandshakeException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: consumeUri.toString(),
        statusCode: null,
        title: 'Erreur TLS',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on FormatException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: consumeUri.toString(),
        statusCode: null,
        title: 'Adresse serveur invalide',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    } on HttpException catch (error) {
      return OpenIrnApiEnrollmentResult(
        status: OpenIrnApiEnrollmentStatus.unreachable,
        url: consumeUri.toString(),
        statusCode: null,
        title: 'Erreur HTTP',
        message: error.message,
        tenantId: safeTenantId,
        enrollmentId: '',
        code: '',
        expiresAt: null,
        expiresInMinutes: 0,
        qrPayloadText: '',
        apiToken: '',
      );
    }
  }

  Future<OpenIrnApiDevicesResult> renameDevice({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required String deviceId,
    required String name,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final renameUri = Uri.parse('$normalizedBaseUrl/devices/$deviceId/rename');

    try {
      final response = await _postJson(renameUri, <String, dynamic>{
        'tenantId': safeTenantId,
        'name': name.trim(),
      }, bearerToken: apiToken);
      return _devicesMutationResult(
        response,
        renameUri,
        safeTenantId,
        successTitle: 'Terminal renommé',
        successMessage: 'Le terminal a été renommé côté serveur.',
      );
    } on TimeoutException {
      return _devicesNetworkError(
        renameUri,
        safeTenantId,
        'Délai dépassé',
        'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return _devicesNetworkError(
        renameUri,
        safeTenantId,
        'Serveur injoignable',
        error.message,
      );
    } on HandshakeException catch (error) {
      return _devicesNetworkError(
        renameUri,
        safeTenantId,
        'Erreur TLS',
        error.message,
      );
    } on FormatException catch (error) {
      return _devicesNetworkError(
        renameUri,
        safeTenantId,
        'Adresse serveur invalide',
        error.message,
      );
    } on HttpException catch (error) {
      return _devicesNetworkError(
        renameUri,
        safeTenantId,
        'Erreur HTTP',
        error.message,
      );
    }
  }

  Future<OpenIrnApiDevicesResult> revokeDevice({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    required String deviceId,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final revokeUri = Uri.parse(
      '$normalizedBaseUrl/devices/$deviceId',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _delete(revokeUri, bearerToken: apiToken);
      return _devicesMutationResult(
        response,
        revokeUri,
        safeTenantId,
        successTitle: 'Terminal révoqué',
        successMessage: 'Le terminal ne peut plus utiliser son jeton.',
      );
    } on TimeoutException {
      return _devicesNetworkError(
        revokeUri,
        safeTenantId,
        'Délai dépassé',
        'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return _devicesNetworkError(
        revokeUri,
        safeTenantId,
        'Serveur injoignable',
        error.message,
      );
    } on HandshakeException catch (error) {
      return _devicesNetworkError(
        revokeUri,
        safeTenantId,
        'Erreur TLS',
        error.message,
      );
    } on FormatException catch (error) {
      return _devicesNetworkError(
        revokeUri,
        safeTenantId,
        'Adresse serveur invalide',
        error.message,
      );
    } on HttpException catch (error) {
      return _devicesNetworkError(
        revokeUri,
        safeTenantId,
        'Erreur HTTP',
        error.message,
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
      'tenantId': tenantId.trim().isEmpty
          ? SyncConfiguration.defaultTenantId
          : tenantId.trim(),
    };
    final since = sinceServerSyncId?.trim();
    if (since != null && since.isNotEmpty) {
      queryParameters['since'] = since;
    }
    final eventsUri = Uri.parse(
      '$normalizedBaseUrl/sync/events',
    ).replace(queryParameters: queryParameters);

    while (true) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(eventsUri).timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
        _applyAuthorizationHeaders(request, bearerToken: apiToken);

        final response = await request.close().timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('SSE refused with HTTP ${response.statusCode}');
        }

        final dataLines = <String>[];
        await for (final line
            in response
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
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

  Future<OfficialReferentialApiResult> loadOfficialReferentialStatus({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final uri = Uri.parse(
      '$normalizedBaseUrl/referential/official/status',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _get(uri, bearerToken: apiToken);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _officialReferentialResult(
          response,
          uri,
          safeTenantId,
          successTitle: 'Référentiel officiel vérifié',
          fallbackSuccessMessage:
              'Le serveur a interrogé le dépôt officiel aDRI IRN.',
        );
      }

      return _officialReferentialRejectedResult(response, uri, safeTenantId);
    } on TimeoutException {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Délai dépassé',
        'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Serveur injoignable',
        error.message,
      );
    } on HandshakeException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Erreur TLS',
        error.message,
      );
    } on FormatException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Adresse serveur invalide',
        error.message,
      );
    } on HttpException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Erreur HTTP',
        error.message,
      );
    }
  }

  Future<OpenIrnApiCurrentReferentialResult> loadCurrentOfficialReferential({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final uri = Uri.parse(
      '$normalizedBaseUrl/referential/official/current',
    ).replace(queryParameters: <String, String>{'tenantId': safeTenantId});

    try {
      final response = await _get(uri, bearerToken: apiToken);
      final decodedBody = _decodeJsonObject(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawReferential = decodedBody?['referential'];
        final referential = rawReferential is Map
            ? IrnReferential.fromJson(Map<String, dynamic>.from(rawReferential))
            : null;

        if (referential == null) {
          return OpenIrnApiCurrentReferentialResult(
            status: OpenIrnApiCurrentReferentialStatus.rejected,
            url: uri.toString(),
            statusCode: response.statusCode,
            title: 'Référentiel serveur invalide',
            message: 'Le serveur a répondu sans objet référentiel exploitable.',
            tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
            summary: _officialReferentialSummary(decodedBody?['summary']),
            responseBody: decodedBody,
          );
        }

        return OpenIrnApiCurrentReferentialResult(
          status: OpenIrnApiCurrentReferentialStatus.available,
          url: uri.toString(),
          statusCode: response.statusCode,
          title: 'Référentiel serveur chargé',
          message:
              'Le référentiel officiel actif a été récupéré depuis le serveur OpenIRN.',
          tenantId: decodedBody?['tenantId']?.toString() ?? safeTenantId,
          referential: referential,
          summary: _officialReferentialSummary(decodedBody?['summary']),
          responseBody: decodedBody,
        );
      }

      return _currentReferentialRejectedResult(response, uri, safeTenantId);
    } on TimeoutException {
      return _currentReferentialNetworkError(
        uri,
        safeTenantId,
        'Délai dépassé',
        'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return _currentReferentialNetworkError(
        uri,
        safeTenantId,
        'Serveur injoignable',
        error.message,
      );
    } on HandshakeException catch (error) {
      return _currentReferentialNetworkError(
        uri,
        safeTenantId,
        'Erreur TLS',
        error.message,
      );
    } on FormatException catch (error) {
      return _currentReferentialNetworkError(
        uri,
        safeTenantId,
        'Adresse serveur invalide',
        error.message,
      );
    } on HttpException catch (error) {
      return _currentReferentialNetworkError(
        uri,
        safeTenantId,
        'Erreur HTTP',
        error.message,
      );
    }
  }

  Future<OfficialReferentialHistoryResult> loadOfficialReferentialHistory({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    int limit = 50,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final uri = Uri.parse('$normalizedBaseUrl/referential/official/history')
        .replace(
          queryParameters: <String, String>{
            'tenantId': safeTenantId,
            'limit': limit.clamp(1, 200).toString(),
          },
        );

    try {
      final response = await _get(uri, bearerToken: apiToken);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _officialReferentialHistoryResult(response, uri, safeTenantId);
      }
      return _officialReferentialHistoryRejectedResult(
        response,
        uri,
        safeTenantId,
      );
    } on TimeoutException {
      return _officialReferentialHistoryNetworkError(
        uri,
        safeTenantId,
        'Délai dépassé',
        'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return _officialReferentialHistoryNetworkError(
        uri,
        safeTenantId,
        'Serveur injoignable',
        error.message,
      );
    } on HandshakeException catch (error) {
      return _officialReferentialHistoryNetworkError(
        uri,
        safeTenantId,
        'Erreur TLS',
        error.message,
      );
    } on FormatException catch (error) {
      return _officialReferentialHistoryNetworkError(
        uri,
        safeTenantId,
        'Adresse serveur invalide',
        error.message,
      );
    } on HttpException catch (error) {
      return _officialReferentialHistoryNetworkError(
        uri,
        safeTenantId,
        'Erreur HTTP',
        error.message,
      );
    }
  }

  Future<OfficialReferentialApiResult> updateOfficialReferential({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
    String triggeredByUserId = '',
    bool force = false,
  }) async {
    final normalizedBaseUrl = SyncConfiguration.normalizeApiBaseUrl(
      baseUrl ?? SyncConfiguration.fixedApiBaseUrl,
    );
    final safeTenantId = tenantId.trim().isEmpty
        ? SyncConfiguration.defaultTenantId
        : tenantId.trim();
    final uri = Uri.parse('$normalizedBaseUrl/referential/official/update');

    try {
      final response = await _postJson(uri, <String, dynamic>{
        'tenantId': safeTenantId,
        'triggeredByUserId': triggeredByUserId,
        'force': force,
      }, bearerToken: apiToken);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _officialReferentialResult(
          response,
          uri,
          safeTenantId,
          successTitle: 'Référentiel officiel mis à jour',
          fallbackSuccessMessage:
              'Le référentiel aDRI IRN a été téléchargé et installé côté serveur.',
        );
      }

      return _officialReferentialRejectedResult(response, uri, safeTenantId);
    } on TimeoutException {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Délai dépassé',
        'Le serveur n’a pas répondu en ${timeout.inSeconds} secondes.',
      );
    } on SocketException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Serveur injoignable',
        error.message,
      );
    } on HandshakeException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Erreur TLS',
        error.message,
      );
    } on FormatException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Adresse serveur invalide',
        error.message,
      );
    } on HttpException catch (error) {
      return _officialReferentialNetworkError(
        uri,
        safeTenantId,
        'Erreur HTTP',
        error.message,
      );
    }
  }

  Future<OpenIrnApiConnectionResult> _tryBaseUrl(
    String normalizedBaseUrl,
  ) async {
    final baseUri = Uri.parse(normalizedBaseUrl);
    try {
      final response = await _get(baseUri);
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.reachable,
        url: baseUri.toString(),
        statusCode: response.statusCode,
        title: 'Serveur joignable',
        message:
            'Le serveur a répondu à l’adresse configurée avec le statut HTTP ${response.statusCode}.',
        responseBody: _decodeJsonObject(response.body),
      );
    } catch (_) {
      return OpenIrnApiConnectionResult(
        reachability: OpenIrnApiReachability.unreachable,
        url: baseUri.toString(),
        statusCode: null,
        title: 'Serveur injoignable',
        message: 'Impossible de joindre l’adresse serveur configurée.',
      );
    }
  }

  void _applyAuthorizationHeaders(
    HttpClientRequest request, {
    String bearerToken = '',
  }) {
    final session = AppSessionManager.instance;
    final trimmedToken = bearerToken.trim().isNotEmpty
        ? bearerToken.trim()
        : session.apiToken;
    if (trimmedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $trimmedToken',
      );
    }
    if (session.deviceId.trim().isNotEmpty) {
      request.headers.set('X-OpenIRN-Device-Id', session.deviceId.trim());
    }
    if (session.tenantId.trim().isNotEmpty) {
      request.headers.set('X-OpenIRN-Tenant-Id', session.tenantId.trim());
    }
  }

  Future<_HttpResponse> _get(Uri uri, {String bearerToken = ''}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      _applyAuthorizationHeaders(request, bearerToken: bearerToken);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _HttpResponse(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  Future<_HttpResponse> _delete(Uri uri, {String bearerToken = ''}) async {
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      _applyAuthorizationHeaders(request, bearerToken: bearerToken);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
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
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      _applyAuthorizationHeaders(request, bearerToken: bearerToken);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _HttpResponse(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  OpenIrnApiDevicesResult _devicesMutationResult(
    _HttpResponse response,
    Uri uri,
    String tenantId, {
    required String successTitle,
    required String successMessage,
  }) {
    final decodedBody = _decodeJsonObject(response.body);
    final rawDevices = decodedBody?['devices'];
    final devices = rawDevices is List
        ? rawDevices
              .whereType<Map>()
              .map(
                (item) =>
                    AuthorizedDevice.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((device) => device.deviceId.trim().isNotEmpty)
              .toList(growable: false)
        : const <AuthorizedDevice>[];

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return OpenIrnApiDevicesResult(
        status: OpenIrnApiDevicesStatus.available,
        url: uri.toString(),
        statusCode: response.statusCode,
        title: successTitle,
        message: successMessage,
        tenantId: decodedBody?['tenantId']?.toString() ?? tenantId,
        devices: devices,
        responseBody: decodedBody,
      );
    }

    return OpenIrnApiDevicesResult(
      status: OpenIrnApiDevicesStatus.rejected,
      url: uri.toString(),
      statusCode: response.statusCode,
      title: 'Opération refusée',
      message:
          decodedBody?['detail']?.toString() ??
          'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
      tenantId: tenantId,
      devices: devices,
      responseBody: decodedBody,
    );
  }

  OpenIrnApiDevicesResult _devicesNetworkError(
    Uri uri,
    String tenantId,
    String title,
    String message,
  ) {
    return OpenIrnApiDevicesResult(
      status: OpenIrnApiDevicesStatus.unreachable,
      url: uri.toString(),
      statusCode: null,
      title: title,
      message: message,
      tenantId: tenantId,
      devices: const <AuthorizedDevice>[],
    );
  }

  OpenIrnApiCurrentReferentialResult _currentReferentialRejectedResult(
    _HttpResponse response,
    Uri uri,
    String tenantId,
  ) {
    final decodedBody = _decodeJsonObject(response.body);
    final detail = decodedBody?['detail'];
    String message;
    if (detail is Map) {
      message =
          detail['message']?.toString() ??
          'Le serveur a refusé le chargement du référentiel officiel.';
    } else {
      message =
          detail?.toString() ??
          'Le serveur a répondu avec le statut HTTP ${response.statusCode}.';
    }

    return OpenIrnApiCurrentReferentialResult(
      status: OpenIrnApiCurrentReferentialStatus.rejected,
      url: uri.toString(),
      statusCode: response.statusCode,
      title: 'Référentiel serveur indisponible',
      message: message,
      tenantId: tenantId,
      summary: _officialReferentialSummary(decodedBody?['summary']),
      responseBody: decodedBody,
    );
  }

  OpenIrnApiCurrentReferentialResult _currentReferentialNetworkError(
    Uri uri,
    String tenantId,
    String title,
    String message,
  ) {
    return OpenIrnApiCurrentReferentialResult(
      status: OpenIrnApiCurrentReferentialStatus.unreachable,
      url: uri.toString(),
      statusCode: null,
      title: title,
      message: message,
      tenantId: tenantId,
    );
  }

  OfficialReferentialApiResult _officialReferentialResult(
    _HttpResponse response,
    Uri uri,
    String tenantId, {
    required String successTitle,
    required String fallbackSuccessMessage,
  }) {
    final decodedBody = _decodeJsonObject(response.body);
    final current = _officialReferentialSummary(decodedBody?['current']);
    final remote = _officialReferentialSummary(decodedBody?['remote']);
    final rawUpdateAvailable = decodedBody?['updateAvailable'];
    final updateAvailable = rawUpdateAvailable is bool
        ? rawUpdateAvailable
        : rawUpdateAvailable?.toString().toLowerCase() == 'true';
    final statusText = decodedBody?['status']?.toString() ?? '';
    final message = decodedBody?['message']?.toString();
    final title = statusText == 'up_to_date'
        ? 'Référentiel officiel déjà à jour'
        : successTitle;

    return OfficialReferentialApiResult(
      status: OfficialReferentialApiStatus.available,
      url: uri.toString(),
      statusCode: response.statusCode,
      title: title,
      message: message == null || message.trim().isEmpty
          ? fallbackSuccessMessage
          : message,
      tenantId: decodedBody?['tenantId']?.toString() ?? tenantId,
      updateAvailable: updateAvailable,
      current: current,
      remote: remote,
      responseBody: decodedBody,
    );
  }

  OfficialReferentialApiResult _officialReferentialRejectedResult(
    _HttpResponse response,
    Uri uri,
    String tenantId,
  ) {
    final decodedBody = _decodeJsonObject(response.body);
    final detail = decodedBody?['detail'];
    String message;
    if (detail is Map) {
      message =
          detail['message']?.toString() ??
          'Le serveur a refusé l’opération sur le référentiel officiel.';
    } else {
      message =
          detail?.toString() ??
          'Le serveur a répondu avec le statut HTTP ${response.statusCode}.';
    }

    return OfficialReferentialApiResult(
      status: OfficialReferentialApiStatus.rejected,
      url: uri.toString(),
      statusCode: response.statusCode,
      title: 'Opération refusée',
      message: message,
      tenantId: tenantId,
      updateAvailable: false,
      current: _officialReferentialSummary(decodedBody?['current']),
      remote: _officialReferentialSummary(decodedBody?['remote']),
      responseBody: decodedBody,
    );
  }

  OfficialReferentialHistoryResult _officialReferentialHistoryResult(
    _HttpResponse response,
    Uri uri,
    String tenantId,
  ) {
    final decodedBody = _decodeJsonObject(response.body);
    final history = _officialReferentialHistory(decodedBody?['history']);
    return OfficialReferentialHistoryResult(
      status: OfficialReferentialApiStatus.available,
      url: uri.toString(),
      statusCode: response.statusCode,
      title: 'Historique référentiel chargé',
      message: history.isEmpty
          ? 'Aucune installation du référentiel officiel n’est historisée pour cet espace.'
          : '${history.length} installation(s) historisée(s) côté serveur.',
      tenantId: decodedBody?['tenantId']?.toString() ?? tenantId,
      history: history,
      responseBody: decodedBody,
    );
  }

  OfficialReferentialHistoryResult _officialReferentialHistoryRejectedResult(
    _HttpResponse response,
    Uri uri,
    String tenantId,
  ) {
    final decodedBody = _decodeJsonObject(response.body);
    final detail = decodedBody?['detail'];
    final message = detail is Map
        ? detail['message']?.toString() ??
              'Le serveur a refusé le chargement de l’historique.'
        : detail?.toString() ??
              'Le serveur a répondu avec le statut HTTP ${response.statusCode}.';
    return OfficialReferentialHistoryResult(
      status: OfficialReferentialApiStatus.rejected,
      url: uri.toString(),
      statusCode: response.statusCode,
      title: 'Historique indisponible',
      message: message,
      tenantId: tenantId,
      history: const <OfficialReferentialSummary>[],
      responseBody: decodedBody,
    );
  }

  OfficialReferentialHistoryResult _officialReferentialHistoryNetworkError(
    Uri uri,
    String tenantId,
    String title,
    String message,
  ) {
    return OfficialReferentialHistoryResult(
      status: OfficialReferentialApiStatus.unreachable,
      url: uri.toString(),
      statusCode: null,
      title: title,
      message: message,
      tenantId: tenantId,
      history: const <OfficialReferentialSummary>[],
    );
  }

  OfficialReferentialApiResult _officialReferentialNetworkError(
    Uri uri,
    String tenantId,
    String title,
    String message,
  ) {
    return OfficialReferentialApiResult(
      status: OfficialReferentialApiStatus.unreachable,
      url: uri.toString(),
      statusCode: null,
      title: title,
      message: message,
      tenantId: tenantId,
      updateAvailable: false,
    );
  }

  OfficialReferentialSummary? _officialReferentialSummary(Object? value) {
    if (value is Map<String, dynamic>) {
      return OfficialReferentialSummary.fromJson(value);
    }
    if (value is Map) {
      return OfficialReferentialSummary.fromJson(
        Map<String, dynamic>.from(value),
      );
    }
    return null;
  }

  List<OfficialReferentialSummary> _officialReferentialHistory(Object? value) {
    if (value is! List) {
      return const <OfficialReferentialSummary>[];
    }
    return value
        .whereType<Map>()
        .map(
          (item) => OfficialReferentialSummary.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((item) => item.exists)
        .toList(growable: false);
  }

  String _enrollmentConsumeErrorTitle(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Code invalide';
      case 404:
        return 'Code inconnu';
      case 409:
        return 'Code déjà utilisé';
      case 410:
        return 'Code expiré';
      case 401:
      case 403:
        return 'Appairage refusé';
    }
    return 'Appairage refusé';
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
