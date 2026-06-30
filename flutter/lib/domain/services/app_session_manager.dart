import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

class AppSessionManager extends ChangeNotifier {
  AppSessionManager._();

  static final AppSessionManager instance = AppSessionManager._();

  static const Duration defaultIdleTimeout = Duration(minutes: 30);

  String _tenantId = '';
  String _deviceId = '';
  String _apiToken = '';
  String _sessionId = '';
  DateTime? _expiresAt;
  DateTime? _lastActivityAt;
  Duration _idleTimeout = defaultIdleTimeout;
  AppUser? _activeUser;
  Timer? _expirationTimer;
  Timer? _idleTimer;
  String _lastLockReason = '';

  String get tenantId => _tenantId;
  String get deviceId => _deviceId;
  String get sessionId => hasActiveSession ? _sessionId.trim() : '';
  String get lastLockReason => _lastLockReason;
  Duration get idleTimeout => _idleTimeout;
  DateTime? get lastActivityAt => _lastActivityAt;

  bool get hasDeviceContext =>
      _tenantId.trim().isNotEmpty && _deviceId.trim().isNotEmpty;

  bool get hasActiveSession {
    final token = _apiToken.trim();
    if (token.isEmpty) {
      return false;
    }
    final expiresAt = _expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
      return false;
    }
    final lastActivityAt = _lastActivityAt;
    if (lastActivityAt != null &&
        DateTime.now().toUtc().difference(lastActivityAt) >= _idleTimeout) {
      return false;
    }
    return true;
  }

  String get apiToken => hasActiveSession ? _apiToken.trim() : '';

  DateTime? get expiresAt => _expiresAt;

  DateTime? get idleExpiresAt {
    final lastActivityAt = _lastActivityAt;
    if (lastActivityAt == null || !hasActiveSession) {
      return null;
    }
    return lastActivityAt.add(_idleTimeout);
  }

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
    String sessionId = '',
    DateTime? expiresAt,
    Duration? idleTimeout,
    AppUser? activeUser,
  }) {
    updateDeviceContext(tenantId: tenantId, deviceId: deviceId);
    _apiToken = apiToken.trim();
    _sessionId = sessionId.trim();
    _expiresAt = expiresAt?.toUtc();
    _idleTimeout = _normalizeIdleTimeout(idleTimeout ?? defaultIdleTimeout);
    _lastActivityAt = DateTime.now().toUtc();
    _activeUser = activeUser;
    _lastLockReason = '';
    _scheduleTimers();
    notifyListeners();
  }

  void setActiveUser(AppUser user) {
    if (!hasActiveSession) {
      return;
    }
    _activeUser = user;
    notifyListeners();
  }

  void registerActivity() {
    if (!hasActiveSession) {
      _clearExpiredSessionIfNeeded();
      return;
    }
    _lastActivityAt = DateTime.now().toUtc();
    _scheduleIdleTimer();
  }

  void validateSession() {
    _clearExpiredSessionIfNeeded();
  }

  void clearSession({String reason = ''}) {
    _expirationTimer?.cancel();
    _idleTimer?.cancel();
    _expirationTimer = null;
    _idleTimer = null;
    _apiToken = '';
    _sessionId = '';
    _expiresAt = null;
    _lastActivityAt = null;
    _idleTimeout = defaultIdleTimeout;
    _activeUser = null;
    _lastLockReason = reason.trim();
    notifyListeners();
  }

  void _clearExpiredSessionIfNeeded() {
    final token = _apiToken.trim();
    if (token.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final expiresAt = _expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      clearSession(reason: 'Session expirée.');
      return;
    }

    final lastActivityAt = _lastActivityAt;
    if (lastActivityAt != null &&
        now.difference(lastActivityAt) >= _idleTimeout) {
      clearSession(reason: 'Session verrouillée après inactivité.');
    }
  }

  void _scheduleTimers() {
    _expirationTimer?.cancel();
    _expirationTimer = null;
    final expiresAt = _expiresAt;
    if (expiresAt != null) {
      final delay = expiresAt.difference(DateTime.now().toUtc());
      _expirationTimer = Timer(
        delay.isNegative ? Duration.zero : delay,
        () => clearSession(reason: 'Session expirée.'),
      );
    }
    _scheduleIdleTimer();
  }

  void _scheduleIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_apiToken.trim().isEmpty) {
      return;
    }
    final lastActivityAt = _lastActivityAt;
    if (lastActivityAt == null) {
      return;
    }
    final delay = lastActivityAt
        .add(_idleTimeout)
        .difference(DateTime.now().toUtc());
    _idleTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => clearSession(reason: 'Session verrouillée après inactivité.'),
    );
  }

  Duration _normalizeIdleTimeout(Duration timeout) {
    if (timeout < const Duration(minutes: 1)) {
      return const Duration(minutes: 1);
    }
    if (timeout > const Duration(hours: 24)) {
      return const Duration(hours: 24);
    }
    return timeout;
  }
}
