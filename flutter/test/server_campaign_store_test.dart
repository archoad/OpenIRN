import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/api/openirn_api_client.dart';
import 'package:openirn/data/repositories/local_sync_configuration_repository.dart';
import 'package:openirn/data/repositories/server_campaign_store.dart';
import 'package:openirn/domain/models/sync_configuration.dart';
import 'package:openirn/domain/services/app_session_manager.dart';

class _TestConfigurationRepository extends LocalSyncConfigurationRepository {
  const _TestConfigurationRepository();

  @override
  Future<SyncConfiguration> loadConfiguration() async {
    return SyncConfiguration.empty(
      tenantId: 'tenant-a',
      deviceId: 'device-a',
    ).copyWith(enabled: true, apiToken: 'ost_test_session');
  }
}

class _RecordingApiClient extends OpenIrnApiClient {
  Map<String, dynamic>? pushedPayload;
  int? deletedExpectedRevision;

  @override
  Future<OpenIrnApiCampaignStatesResult> loadCampaignStates({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    return const OpenIrnApiCampaignStatesResult(
      status: OpenIrnApiCampaignStatesStatus.available,
      statusCode: 200,
      campaigns: <OpenIrnApiCampaignState>[
        OpenIrnApiCampaignState(
          campaignId: '11111111-1111-4111-8111-111111111111',
          serverRevision: 7,
          payload: <String, dynamic>{
            'campaign': <String, dynamic>{
              'id': '11111111-1111-4111-8111-111111111111',
              'referentialId': 'adri-irn-v1.1',
              'name': 'Campaign A',
              'createdAt': '2026-08-24T09:00:00Z',
              'updatedAt': '2026-08-24T10:00:00Z',
              'statusUpdatedAt': '2026-08-24T09:00:00Z',
            },
            'answers': <Map<String, dynamic>>[],
            'assignments': <Map<String, dynamic>>[],
            'activityLog': <String, dynamic>{
              'eventCount': 0,
              'events': <Map<String, dynamic>>[],
            },
          },
        ),
      ],
    );
  }

  @override
  Future<OpenIrnApiPushResult> pushPayload({
    String? baseUrl,
    required Map<String, dynamic> payload,
    String apiToken = '',
  }) async {
    pushedPayload = payload;
    return const OpenIrnApiPushResult(
      status: OpenIrnApiPushStatus.accepted,
      url: 'https://example.test/api/sync/push',
      statusCode: 200,
      title: 'accepted',
      message: 'accepted',
    );
  }

  @override
  Future<OpenIrnApiCampaignDeleteResult> deleteCampaign({
    String? baseUrl,
    required String tenantId,
    required String campaignId,
    required int expectedRevision,
    String apiToken = '',
  }) async {
    deletedExpectedRevision = expectedRevision;
    return OpenIrnApiCampaignDeleteResult(
      status: OpenIrnApiCampaignDeleteStatus.deleted,
      statusCode: 200,
      campaignId: campaignId,
      deletedRevision: expectedRevision,
    );
  }
}

class _RetryingApiClient extends OpenIrnApiClient {
  final bool rejectEveryRequest;
  final List<String> receivedTokens = <String>[];

  _RetryingApiClient({this.rejectEveryRequest = false});

  @override
  Future<OpenIrnApiCampaignStatesResult> loadCampaignStates({
    String? baseUrl,
    required String tenantId,
    String apiToken = '',
  }) async {
    receivedTokens.add(apiToken);
    if (rejectEveryRequest || receivedTokens.length == 1) {
      return const OpenIrnApiCampaignStatesResult(
        status: OpenIrnApiCampaignStatesStatus.rejected,
        statusCode: 403,
        campaigns: <OpenIrnApiCampaignState>[],
        errorDetail: 'Session expirée ou autorisation OpenIRN invalide',
      );
    }
    return const OpenIrnApiCampaignStatesResult(
      status: OpenIrnApiCampaignStatesStatus.available,
      statusCode: 200,
      campaigns: <OpenIrnApiCampaignState>[],
    );
  }
}

void main() {
  group('ServerCampaignStore data integrity', () {
    late _RecordingApiClient apiClient;
    late ServerCampaignStore store;

    setUp(() {
      apiClient = _RecordingApiClient();
      store = ServerCampaignStore(
        configurationRepository: const _TestConfigurationRepository(),
        apiClient: apiClient,
      );
    });

    test(
      'loads bundles from current campaign states with their revision',
      () async {
        final bundles = await store.loadBundles(referentialId: 'adri-irn-v1.1');

        expect(bundles, hasLength(1));
        expect(bundles.single.campaign.name, 'Campaign A');
        expect(bundles.single.serverRevision, 7);
      },
    );

    test(
      'publishes the expected server revision with every campaign',
      () async {
        final bundles = await store.loadBundles(referentialId: 'adri-irn-v1.1');
        await store.saveBundles(
          referentialId: 'adri-irn-v1.1',
          bundles: bundles,
        );

        final campaigns = apiClient.pushedPayload!['campaigns'] as List;
        final campaign = Map<String, dynamic>.from(campaigns.single as Map);
        expect(campaign['expectedServerRevision'], 7);
      },
    );

    test(
      'deletes through the explicit endpoint with the loaded revision',
      () async {
        await store.deleteBundle(
          referentialId: 'adri-irn-v1.1',
          campaignId: '11111111-1111-4111-8111-111111111111',
        );

        expect(apiClient.deletedExpectedRevision, 7);
        expect(apiClient.pushedPayload, isNull);
      },
    );
  });

  group('ServerCampaignStore session recovery', () {
    setUp(() {
      AppSessionManager.instance.clearDeviceCredential();
      AppSessionManager.instance.startSession(
        apiToken: 'ost_current_session',
        tenantId: 'tenant-a',
        deviceId: 'device-a',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
    });

    tearDown(() {
      AppSessionManager.instance.clearDeviceCredential();
      AppSessionManager.instance.updateDeviceContext(
        tenantId: '',
        deviceId: '',
      );
    });

    test('retries one rejected read with the current session token', () async {
      final apiClient = _RetryingApiClient();
      final store = ServerCampaignStore(
        configurationRepository: const _TestConfigurationRepository(),
        apiClient: apiClient,
      );

      final bundles = await store.loadBundles(referentialId: 'adri-irn-v1.1');

      expect(bundles, isEmpty);
      expect(apiClient.receivedTokens, <String>[
        'ost_test_session',
        'ost_current_session',
      ]);
    });

    test('stops after one retry when authorization remains rejected', () async {
      final apiClient = _RetryingApiClient(rejectEveryRequest: true);
      final store = ServerCampaignStore(
        configurationRepository: const _TestConfigurationRepository(),
        apiClient: apiClient,
      );

      await expectLater(
        store.loadBundles(referentialId: 'adri-irn-v1.1'),
        throwsA(isA<ServerCampaignStoreException>()),
      );
      expect(apiClient.receivedTokens, hasLength(2));
    });
  });
}
