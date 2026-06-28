import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../models/app_user.dart';
import '../models/irn_referential.dart';
import 'sync_automation_service.dart';

enum AppSyncState {
  idle,
  localOnly,
  listening,
  checking,
  imported,
  pushed,
  offline,
  failed,
}

class AppSyncCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  static final AppSyncCoordinator instance = AppSyncCoordinator._();

  final SyncAutomationService _syncAutomationService;
  final LocalSyncConfigurationRepository _configurationRepository;

  AppSyncCoordinator._({
    SyncAutomationService? syncAutomationService,
    LocalSyncConfigurationRepository? configurationRepository,
  }) : _syncAutomationService =
           syncAutomationService ?? const SyncAutomationService(),
       _configurationRepository =
           configurationRepository ?? const LocalSyncConfigurationRepository();

  IrnReferential? _referential;
  AppUser? _lastActiveUser;
  Timer? _pollTimer;
  Timer? _pushDebounceTimer;
  Timer? _remoteEventReconnectTimer;
  StreamSubscription<OpenIrnSyncEvent>? _remoteEventSubscription;
  bool _observingLifecycle = false;
  bool _foregroundLoopsStarted = false;
  bool _syncRunning = false;
  bool _pendingPull = false;
  bool _pendingPush = false;
  String? _lastRemoteEventServerSyncId;
  int _changeSerial = 0;
  AppSyncState _state = AppSyncState.idle;
  String _title = 'Synchronisation en attente';
  String _message =
      'La synchronisation de fond sera lancée au chargement du référentiel.';
  DateTime? _lastImportedAt;
  DateTime? _lastPushedAt;
  DateTime? _lastCheckedAt;

  AppSyncState get state => _state;
  String get title => _title;
  String get message => _message;
  int get changeSerial => _changeSerial;
  DateTime? get lastImportedAt => _lastImportedAt;
  DateTime? get lastPushedAt => _lastPushedAt;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  bool get hasImportedRemoteData => _lastImportedAt != null;

  void start({required IrnReferential referential}) {
    _referential = referential;
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    _startForegroundLoops();
  }

  void stop() {
    _foregroundLoopsStarted = false;
    _pollTimer?.cancel();
    _pushDebounceTimer?.cancel();
    _remoteEventReconnectTimer?.cancel();
    _remoteEventSubscription?.cancel();
    _pollTimer = null;
    _pushDebounceTimer = null;
    _remoteEventReconnectTimer = null;
    _remoteEventSubscription = null;
    _setState(
      AppSyncState.idle,
      title: 'Synchronisation arrêtée',
      message: 'La synchronisation de fond est suspendue.',
    );
  }

  void schedulePush({AppUser? activeUser}) {
    _lastActiveUser = activeUser ?? _lastActiveUser;
    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = Timer(
      const Duration(seconds: 3),
      () => pushNow(activeUser: _lastActiveUser),
    );
  }

  Future<void> pushNow({AppUser? activeUser}) async {
    final referential = _referential;
    if (referential == null) {
      return;
    }
    _lastActiveUser = activeUser ?? _lastActiveUser;

    if (_syncRunning) {
      _pendingPush = true;
      return;
    }

    _syncRunning = true;
    _setState(
      AppSyncState.checking,
      title: 'Publication en cours',
      message: 'Publication automatique de ce terminal vers le serveur.',
    );

    try {
      final result = await _syncAutomationService.pushLocalSnapshot(
        referential: referential,
        activeUser: activeUser ?? _lastActiveUser,
      );
      _applyResult(result, fromPush: true);
    } catch (error) {
      _setState(
        AppSyncState.failed,
        title: 'Publication automatique impossible',
        message: error.toString(),
      );
    } finally {
      _syncRunning = false;
      _drainPendingWork();
    }
  }

  Future<void> pullLatestNow() async {
    final referential = _referential;
    if (referential == null) {
      return;
    }

    if (_syncRunning) {
      _pendingPull = true;
      return;
    }

    _syncRunning = true;
    _setState(
      AppSyncState.checking,
      title: 'Contrôle serveur en cours',
      message: 'Recherche d’une version serveur plus récente.',
    );

    try {
      final result = await _syncAutomationService.pullLatestIfRemoteNewer(
        referential: referential,
      );
      _applyResult(result, fromPush: false);
      if (result.outcome != SyncAutomationOutcome.localOnly) {
        _ensureRealtimeListener();
      }
    } catch (error) {
      _setState(
        AppSyncState.failed,
        title: 'Synchronisation automatique impossible',
        message: error.toString(),
      );
    } finally {
      _syncRunning = false;
      _drainPendingWork();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundLoops();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopForegroundLoopsOnly();
    }
  }

  void _startForegroundLoops() {
    if (_referential == null || _foregroundLoopsStarted) {
      return;
    }
    _foregroundLoopsStarted = true;
    _setState(
      AppSyncState.checking,
      title: 'Synchronisation de fond active',
      message:
          'OpenIRN contrôle le serveur pendant toute l’utilisation de l’application.',
    );
    _startPolling();
    _ensureRealtimeListener();
    Future<void>.delayed(Duration.zero, pullLatestNow);
  }

  void _stopForegroundLoopsOnly() {
    _foregroundLoopsStarted = false;
    _pollTimer?.cancel();
    _pushDebounceTimer?.cancel();
    _remoteEventReconnectTimer?.cancel();
    _remoteEventSubscription?.cancel();
    _pollTimer = null;
    _pushDebounceTimer = null;
    _remoteEventReconnectTimer = null;
    _remoteEventSubscription = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => pullLatestNow(),
    );
  }

  Future<void> _ensureRealtimeListener() async {
    if (!_foregroundLoopsStarted || _remoteEventSubscription != null) {
      return;
    }

    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      _setState(
        AppSyncState.localOnly,
        title: 'Mode hors ligne uniquement',
        message:
            'La synchronisation de fond attend une configuration API complète.',
      );
      return;
    }

    _remoteEventReconnectTimer?.cancel();
    _remoteEventSubscription = _syncAutomationService
        .watchRemoteEvents(sinceServerSyncId: _lastRemoteEventServerSyncId)
        .listen(
          (event) {
            final serverSyncId = event.serverSyncId.trim();
            if (serverSyncId.isEmpty ||
                serverSyncId == _lastRemoteEventServerSyncId) {
              return;
            }
            _lastRemoteEventServerSyncId = serverSyncId;
            pullLatestNow();
          },
          onError: (_) => _scheduleRealtimeReconnect(),
          onDone: _scheduleRealtimeReconnect,
          cancelOnError: false,
        );

    _setState(
      AppSyncState.listening,
      title: 'Synchronisation temps réel active',
      message:
          'OpenIRN écoute les changements publiés par les autres terminaux.',
    );
  }

  void _scheduleRealtimeReconnect() {
    _remoteEventSubscription?.cancel();
    _remoteEventSubscription = null;
    if (!_foregroundLoopsStarted) {
      return;
    }
    _remoteEventReconnectTimer?.cancel();
    _remoteEventReconnectTimer = Timer(
      const Duration(seconds: 5),
      _ensureRealtimeListener,
    );
  }

  void _applyResult(SyncAutomationResult result, {required bool fromPush}) {
    _lastCheckedAt = DateTime.now().toUtc();

    switch (result.outcome) {
      case SyncAutomationOutcome.localOnly:
        _setState(
          AppSyncState.localOnly,
          title: result.title,
          message: result.message,
        );
        break;
      case SyncAutomationOutcome.offline:
        _setState(
          AppSyncState.offline,
          title: result.title,
          message: result.message,
        );
        break;
      case SyncAutomationOutcome.failed:
        _setState(
          AppSyncState.failed,
          title: result.title,
          message: result.message,
        );
        break;
      case SyncAutomationOutcome.imported:
        _lastImportedAt = DateTime.now().toUtc();
        _changeSerial++;
        _setState(
          AppSyncState.imported,
          title: result.title,
          message: result.message,
        );
        break;
      case SyncAutomationOutcome.pushed:
        _lastPushedAt = DateTime.now().toUtc();
        _setState(
          AppSyncState.pushed,
          title: result.title,
          message: result.message,
        );
        break;
      case SyncAutomationOutcome.upToDate:
        _setState(
          AppSyncState.listening,
          title: fromPush ? 'Version locale publiée' : 'Données à jour',
          message: result.message,
        );
        break;
    }
  }

  void _drainPendingWork() {
    if (_pendingPush) {
      _pendingPush = false;
      Future<void>.delayed(
        const Duration(seconds: 1),
        () => pushNow(activeUser: _lastActiveUser),
      );
      return;
    }
    if (_pendingPull) {
      _pendingPull = false;
      Future<void>.delayed(const Duration(seconds: 1), pullLatestNow);
    }
  }

  void _setState(
    AppSyncState state, {
    required String title,
    required String message,
  }) {
    _state = state;
    _title = title;
    _message = message;
    notifyListeners();
  }
}
