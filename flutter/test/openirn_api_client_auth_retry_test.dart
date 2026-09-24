import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/api/openirn_api_client.dart';
import 'package:openirn/domain/services/app_session_manager.dart';

void main() {
  late HttpServer server;
  final receivedTokens = <String>[];
  final receivedMethods = <String>[];
  var responseStatusCodes = <int>[];
  String? rotateSessionTokenAfterRejection;
  var rejectionDetail = 'Session expirée ou autorisation OpenIRN invalide';

  setUp(() async {
    receivedTokens.clear();
    receivedMethods.clear();
    responseStatusCodes = <int>[];
    rotateSessionTokenAfterRejection = null;
    rejectionDetail = 'Session expirée ou autorisation OpenIRN invalide';
    AppSessionManager.instance.clearDeviceCredential();
    AppSessionManager.instance.startSession(
      apiToken: 'ost_current_session',
      tenantId: 'tenant-a',
      deviceId: 'device-a',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      receivedTokens.add(
        request.headers.value(HttpHeaders.authorizationHeader) ?? '',
      );
      receivedMethods.add(request.method);
      final statusCode = responseStatusCodes.removeAt(0);
      request.response.statusCode = statusCode;
      if (statusCode == HttpStatus.ok &&
          request.uri.path.endsWith('/sync/events')) {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: ${jsonEncode(<String, Object>{'type': 'openirn.syncEvent', 'tenantId': 'tenant-a', 'serverSyncId': 'sync-1', 'campaignCount': 1})}\n\n',
        );
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            statusCode == HttpStatus.ok
                ? request.uri.path.endsWith('/sync/push')
                      ? <String, Object>{'serverSyncId': 'sync-1'}
                      : <String, Object>{
                          'status': 'ok',
                          'tenantId': 'tenant-a',
                          'snapshotCount': 0,
                          'deviceCount': 1,
                          'campaignCount': 0,
                        }
                : <String, Object>{'detail': rejectionDetail},
          ),
        );
      }
      if (statusCode != HttpStatus.ok &&
          rotateSessionTokenAfterRejection != null) {
        AppSessionManager.instance.startSession(
          apiToken: rotateSessionTokenAfterRejection!,
          tenantId: 'tenant-a',
          deviceId: 'device-a',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    AppSessionManager.instance.clearDeviceCredential();
    AppSessionManager.instance.updateDeviceContext(tenantId: '', deviceId: '');
  });

  test(
    'uses the current session and retries one transient GET rejection',
    () async {
      responseStatusCodes = <int>[HttpStatus.forbidden, HttpStatus.ok];

      final result = await const OpenIrnApiClient().loadSyncStatus(
        baseUrl:
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
        tenantId: 'tenant-a',
        apiToken: 'ost_stale_session',
      );

      expect(result.isAvailable, isTrue);
      expect(receivedTokens, <String>[
        'Bearer ost_current_session',
        'Bearer ost_current_session',
      ]);
    },
  );

  test(
    'stops after one retry when the current session stays rejected',
    () async {
      responseStatusCodes = <int>[HttpStatus.forbidden, HttpStatus.forbidden];

      final result = await const OpenIrnApiClient().loadSyncStatus(
        baseUrl:
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
        tenantId: 'tenant-a',
        apiToken: 'ost_current_session',
      );

      expect(result.isAvailable, isFalse);
      expect(receivedTokens, <String>[
        'Bearer ost_current_session',
        'Bearer ost_current_session',
      ]);
    },
  );

  test('retries a transient authenticated write only once', () async {
    responseStatusCodes = <int>[HttpStatus.forbidden, HttpStatus.ok];

    final result = await const OpenIrnApiClient().pushPayload(
      baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
      apiToken: 'ost_current_session',
      payload: const <String, Object>{'campaigns': <Object>[]},
    );

    expect(result.isAccepted, isTrue);
    expect(receivedMethods, <String>['POST', 'POST']);
    expect(receivedTokens, <String>[
      'Bearer ost_current_session',
      'Bearer ost_current_session',
    ]);
  });

  test('does not retry a real role authorization denial', () async {
    responseStatusCodes = <int>[HttpStatus.forbidden];
    rejectionDetail = 'Votre profil ne permet pas cette opération';

    final result = await const OpenIrnApiClient().loadSyncStatus(
      baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
      tenantId: 'tenant-a',
      apiToken: 'ost_current_session',
    );

    expect(result.isAvailable, isFalse);
    expect(receivedTokens, <String>['Bearer ost_current_session']);
  });

  test('SSE reconnects with a session rotated after rejection', () async {
    responseStatusCodes = <int>[HttpStatus.forbidden, HttpStatus.ok];
    rotateSessionTokenAfterRejection = 'ost_rotated_session';

    final event = await const OpenIrnApiClient()
        .watchSyncEvents(
          baseUrl:
              'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
          tenantId: 'tenant-a',
          apiToken: 'ost_current_session',
          reconnectDelay: const Duration(milliseconds: 10),
        )
        .first;

    expect(event.serverSyncId, 'sync-1');
    expect(receivedTokens, <String>[
      'Bearer ost_current_session',
      'Bearer ost_rotated_session',
    ]);
  });
}
