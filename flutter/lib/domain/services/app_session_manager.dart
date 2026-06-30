import '../models/app_user.dart';

class AppSessionManager {
  AppSessionManager._();

  static final AppSessionManager instance = AppSessionManager._();

  String _tenantId = '';
  String _deviceId = '';
  String _apiToken = '';
  DateTime? _expiresAt;
  AppUser? _activeUser;

  String get tenantId => _tenantId;
  String get deviceId => _deviceId;

  bool get hasDeviceContext =>
      _tenantId.trim().isNotEmpty && _deviceId.trim().isNotEmpty;

  bool get hasActiveSession {
    final token = _apiToken.trim();
    if (token.isEmpty) {
      return false;
    }
    final expiresAt = _expiresAt;
    if (expiresAt == null) {
      return true;
    }
    return expiresAt.isAfter(DateTime.now().toUtc());
  }

  String get apiToken => hasActiveSession ? _apiToken.trim() : '';

  DateTime? get expiresAt => _expiresAt;

  AppUser? get activeUser => hasActiveSession ? _activeUser : null;

  void updateDeviceContext({
    required String tenantId,
    required String deviceId,
  }) {
    _tenantId = tenantId.trim();
    _deviceId = deviceId.trim();
  }

  void startSession({
    required String apiToken,
    required String tenantId,
    required String deviceId,
    DateTime? expiresAt,
    AppUser? activeUser,
  }) {
    updateDeviceContext(tenantId: tenantId, deviceId: deviceId);
    _apiToken = apiToken.trim();
    _expiresAt = expiresAt?.toUtc();
    _activeUser = activeUser;
  }

  void setActiveUser(AppUser user) {
    _activeUser = user;
  }

  void clearSession() {
    _apiToken = '';
    _expiresAt = null;
    _activeUser = null;
  }
}
