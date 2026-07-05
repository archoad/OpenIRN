import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../l10n/openirn_localizations.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/services/app_session_manager.dart';

enum _ConnectivityState { tenantNotSelected, checking, online, localOnly }

class SyncConnectivityIndicator extends StatefulWidget {
  final Duration refreshInterval;

  const SyncConnectivityIndicator({
    this.refreshInterval = const Duration(seconds: 30),
    super.key,
  });

  @override
  State<SyncConnectivityIndicator> createState() =>
      _SyncConnectivityIndicatorState();
}

class _SyncConnectivityIndicatorState extends State<SyncConnectivityIndicator> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient(timeout: Duration(seconds: 5));

  Timer? _timer;
  _ConnectivityState _state = _ConnectivityState.checking;
  String _tooltipKey = 'sync.tooltip.checking';
  String? _tooltipFallback;
  int? _snapshotCount;
  String? _offlineTitle;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final activeTenantId = AppSessionManager.instance.tenantId.trim();
    if (activeTenantId.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _state = _ConnectivityState.tenantNotSelected;
        _tooltipKey = 'sync.tooltip.no_tenant';
        _tooltipFallback =
            'Aucun espace de travail sélectionné : aucune connexion au serveur n’est ouverte.';
        _snapshotCount = null;
        _offlineTitle = null;
      });
      return;
    }

    final configuration = await _configurationRepository.loadConfiguration();
    if (!mounted) {
      return;
    }

    if (!configuration.isConfigured ||
        !configuration.hasSelectedTenant ||
        configuration.tenantId != activeTenantId) {
      setState(() {
        _state = _ConnectivityState.localOnly;
        _tooltipKey = 'sync.tooltip.local_only';
        _tooltipFallback =
            'Mode hors ligne uniquement : synchronisation non configurée pour l’espace courant.';
        _snapshotCount = null;
        _offlineTitle = null;
      });
      return;
    }

    setState(() {
      _state = _ConnectivityState.checking;
      _tooltipKey = 'sync.tooltip.checking';
      _tooltipFallback = 'Contrôle de la connexion OpenIRN…';
      _snapshotCount = null;
      _offlineTitle = null;
    });

    final result = await _apiClient.loadSyncStatus(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _state = result.isAvailable
          ? _ConnectivityState.online
          : _ConnectivityState.localOnly;
      if (result.isAvailable) {
        _tooltipKey = 'sync.tooltip.online';
        _tooltipFallback =
            'Synchronisation OpenIRN active : ${result.snapshotCount} snapshot(s) serveur.';
        _snapshotCount = result.snapshotCount;
        _offlineTitle = null;
      } else {
        _tooltipKey = 'sync.tooltip.offline_title';
        _tooltipFallback = 'Mode hors ligne uniquement : ${result.title}';
        _snapshotCount = null;
        _offlineTitle = result.title;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tooltip = context.tr(
      _tooltipKey,
      fallback: _tooltipFallback ?? 'Contrôle de la connexion OpenIRN…',
      values: {'count': _snapshotCount ?? '', 'title': _offlineTitle ?? ''},
    );
    final color = switch (_state) {
      _ConnectivityState.tenantNotSelected => colorScheme.outline,
      _ConnectivityState.checking => colorScheme.tertiary,
      _ConnectivityState.online => Colors.green,
      _ConnectivityState.localOnly => colorScheme.error,
    };
    final label = switch (_state) {
      _ConnectivityState.tenantNotSelected => context.tr(
        'sync.status.no_tenant',
        fallback: 'Aucun espace sélectionné',
      ),
      _ConnectivityState.checking => context.tr(
        'sync.status.checking',
        fallback: 'Contrôle en cours',
      ),
      _ConnectivityState.online => context.tr(
        'sync.status.online',
        fallback: 'Serveur accessible',
      ),
      _ConnectivityState.localOnly => context.tr(
        'sync.status.local_only',
        fallback: 'Mode hors ligne',
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: context.tr(
          'sync.semantics.status',
          fallback: 'Statut de synchronisation : {label}',
          values: {'label': label},
        ),
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _refresh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.25),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
