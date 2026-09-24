import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_user.dart';
import '../api/openirn_api_client.dart';
import 'local_sync_configuration_repository.dart';

class LocalUserRepository {
  const LocalUserRepository({
    this.syncConfigurationRepository = const LocalSyncConfigurationRepository(),
    this.apiClient = const OpenIrnApiClient(),
  });

  static const _legacyStorageKey = 'openirn.localUsers';

  final LocalSyncConfigurationRepository syncConfigurationRepository;
  final OpenIrnApiClient apiClient;

  Future<List<AppUser>> loadUsers() async {
    await _purgeLegacyLocalUsers();

    final configuration = await syncConfigurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return const <AppUser>[];
    }

    final result = await apiClient.loadUsers(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );

    if (result.isAvailable || result.status == OpenIrnApiUsersStatus.empty) {
      return _sortUsers(result.users);
    }

    throw LocalUserRepositoryException('${result.title} — ${result.message}');
  }

  Future<List<AppUser>> ensureDefaultUsers() async {
    return loadUsers();
  }

  List<AppUser> _sortUsers(List<AppUser> users) {
    final sorted = users.toList();
    sorted.sort((a, b) {
      final activeWeightA = a.active ? 0 : 1;
      final activeWeightB = b.active ? 0 : 1;
      if (activeWeightA != activeWeightB) {
        return activeWeightA.compareTo(activeWeightB);
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return sorted;
  }

  Future<void> _purgeLegacyLocalUsers() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyStorageKey);
  }
}

class LocalUserRepositoryException implements Exception {
  final String message;

  const LocalUserRepositoryException(this.message);

  @override
  String toString() => message;
}
