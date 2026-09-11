import '../../domain/models/irn_referential.dart';
import '../../domain/repositories/irn_referential_repository.dart';
import '../api/openirn_api_client.dart';
import 'local_sync_configuration_repository.dart';

class ApiIrnReferentialRepository implements IrnReferentialRepository {
  final LocalSyncConfigurationRepository configurationRepository;
  final OpenIrnApiClient apiClient;

  const ApiIrnReferentialRepository({
    this.configurationRepository = const LocalSyncConfigurationRepository(),
    this.apiClient = const OpenIrnApiClient(),
  });

  @override
  Future<IrnReferential> getActiveReferential() async {
    final configuration = await configurationRepository.loadConfiguration();

    if (!configuration.isConfigured) {
      throw const ApiIrnReferentialException(
        'Terminal non autorisé : le référentiel serveur ne peut pas être chargé avant appairage.',
      );
    }

    final result = await apiClient.loadCurrentOfficialReferential(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
    );

    final referential = result.referential;
    if (result.isAvailable && referential != null) {
      return referential;
    }

    throw ApiIrnReferentialException(
      '${result.title} — ${result.message}',
      statusCode: result.statusCode,
    );
  }
}

class ApiIrnReferentialException implements Exception {
  final String message;
  final int? statusCode;

  const ApiIrnReferentialException(this.message, {this.statusCode});

  bool get requiresDeviceEnrollment => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}
