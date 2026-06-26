import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';

enum _ConnectivityState {
  checking,
  online,
  localOnly,
}

class SyncConnectivityIndicator extends StatefulWidget {
  final Duration refreshInterval;

  const SyncConnectivityIndicator({
    this.refreshInterval = const Duration(seconds: 30),
    super.key,
  });

  @override
  State<SyncConnectivityIndicator> createState() => _SyncConnectivityIndicatorState();
}

class _SyncConnectivityIndicatorState extends State<SyncConnectivityIndicator> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient(timeout: Duration(seconds: 5));

  Timer? _timer;
  _ConnectivityState _state = _ConnectivityState.checking;
  String _tooltip = 'Contrôle de la connexion OpenIRN…';

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
    final configuration = await _configurationRepository.loadConfiguration();
    if (!mounted) {
      return;
    }

    if (!configuration.isConfigured) {
      setState(() {
        _state = _ConnectivityState.localOnly;
        _tooltip = 'Mode hors ligne uniquement : synchronisation non configurée ou désactivée.';
      });
      return;
    }

    setState(() {
      _state = _ConnectivityState.checking;
      _tooltip = 'Contrôle de la connexion OpenIRN…';
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
      _state = result.isAvailable ? _ConnectivityState.online : _ConnectivityState.localOnly;
      _tooltip = result.isAvailable
          ? 'Synchronisation OpenIRN active : ${result.snapshotCount} snapshot(s) serveur.'
          : 'Mode hors ligne uniquement : ${result.title}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (_state) {
      _ConnectivityState.checking => colorScheme.tertiary,
      _ConnectivityState.online => Colors.green,
      _ConnectivityState.localOnly => colorScheme.error,
    };
    final label = switch (_state) {
      _ConnectivityState.checking => 'Contrôle en cours',
      _ConnectivityState.online => 'Serveur accessible',
      _ConnectivityState.localOnly => 'Mode hors ligne',
    };

    return Tooltip(
      message: _tooltip,
      child: Semantics(
        label: 'Statut de synchronisation : $label',
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
