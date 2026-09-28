import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/api/openirn_api_client.dart';

void main() {
  late HttpServer server;
  late Uri receivedUri;
  late String receivedMethod;
  late List<int> receivedBody;
  var sendFileNameHeader = true;

  setUp(() async {
    receivedBody = <int>[];
    sendFileNameHeader = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      receivedUri = request.uri;
      receivedMethod = request.method;
      receivedBody = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      request.response.statusCode = HttpStatus.ok;
      if (request.method == 'GET') {
        if (sendFileNameHeader) {
          request.response.headers.set(
            'content-disposition',
            'attachment; filename="20260925_openirn_export.xlsx"',
          );
        }
        request.response.add(<int>[80, 75, 3, 4]);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object>{
            'status': 'ok',
            'tenantId': 'tenant-a',
            'tenantDisplayName': 'Espace A',
            'criticalFunctions': <Object>[],
            'informationSystems': <Object>[],
            'assets': <Object>[],
            'message': 'Répartition importée.',
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'exports the complete inventory graph from the dedicated endpoint',
    () async {
      final result = await const OpenIrnApiClient().exportInventoryGraphExcel(
        baseUrl:
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
        tenantId: 'tenant-a',
        apiToken: 'token-a',
      );

      expect(result.isAvailable, isTrue);
      expect(result.suggestedFileName, '20260925_openirn_export.xlsx');
      expect(receivedMethod, 'GET');
      expect(receivedUri.path, '/inventory/graph/export.xlsx');
      expect(receivedUri.queryParameters['tenantId'], 'tenant-a');
    },
  );

  test(
    'imports the complete inventory graph in replace-relations mode',
    () async {
      final bytes = Uint8List.fromList(<int>[80, 75, 3, 4]);
      final result = await const OpenIrnApiClient().importInventoryGraphExcel(
        baseUrl:
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
        tenantId: 'tenant-a',
        apiToken: 'token-a',
        bytes: bytes,
      );

      expect(result.isAvailable, isTrue);
      expect(receivedMethod, 'POST');
      expect(receivedUri.path, '/inventory/graph/import.xlsx');
      expect(receivedUri.queryParameters, <String, String>{
        'tenantId': 'tenant-a',
        'mode': 'replace-relations',
      });
      expect(receivedBody, bytes);
    },
  );

  test(
    'uses the requested export filename format without a server name',
    () async {
      sendFileNameHeader = false;

      final result = await const OpenIrnApiClient().exportInventoryGraphExcel(
        baseUrl:
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
        tenantId: 'tenant-a',
        apiToken: 'token-a',
      );

      expect(result.isAvailable, isTrue);
      expect(
        result.suggestedFileName,
        matches(RegExp(r'^\d{8}_openirn_export\.xlsx$')),
      );
    },
  );
}
