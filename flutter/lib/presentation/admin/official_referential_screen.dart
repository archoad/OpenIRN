import 'package:flutter/material.dart';

import '../../data/api/openirn_api_client.dart';
import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/official_referential.dart';
import '../../domain/models/sync_configuration.dart';
import '../common/openirn_app_bar.dart';

class OfficialReferentialScreen extends StatefulWidget {
  final AppUser activeUser;

  const OfficialReferentialScreen({required this.activeUser, super.key});

  @override
  State<OfficialReferentialScreen> createState() =>
      _OfficialReferentialScreenState();
}

class _OfficialReferentialScreenState extends State<OfficialReferentialScreen> {
  final _configurationRepository = const LocalSyncConfigurationRepository();
  final _apiClient = const OpenIrnApiClient(timeout: Duration(seconds: 45));

  late Future<_OfficialReferentialStateData> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = _loadStatus();
  }

  Future<_OfficialReferentialStateData> _loadStatus() async {
    final configuration = await _configurationRepository.loadConfiguration();
    if (!configuration.isConfigured) {
      return _OfficialReferentialStateData(
        configuration: configuration,
        result: OfficialReferentialApiResult(
          status: OfficialReferentialApiStatus.unreachable,
          url: configuration.apiBaseUrl,
          statusCode: null,
          title: 'API non configurée',
          message:
              'La synchronisation serveur n’est pas configurée sur ce terminal.',
          tenantId: configuration.tenantId,
          updateAvailable: false,
        ),
      );
    }

    final result = await _apiClient.loadOfficialReferentialStatus(
      baseUrl: configuration.apiBaseUrl,
      tenantId: configuration.tenantId,
      apiToken: configuration.apiToken,
    );
    return _OfficialReferentialStateData(
      configuration: configuration,
      result: result,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadStatus();
    });
    await _future;
  }

  Future<void> _update(_OfficialReferentialStateData state) async {
    if (_working || !state.configuration.isConfigured) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final remote = state.result.remote;
        return AlertDialog(
          title: const Text('Mettre à jour le référentiel officiel ?'),
          content: Text(
            remote == null
                ? 'OpenIRN va interroger le dépôt officiel aDRI, télécharger le dernier fichier détecté, le valider puis l’installer côté serveur.'
                : 'OpenIRN va télécharger ${remote.version} depuis le dépôt officiel aDRI, le valider puis l’installer côté serveur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Mettre à jour'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      final result = await _apiClient.updateOfficialReferential(
        baseUrl: state.configuration.apiBaseUrl,
        tenantId: state.configuration.tenantId,
        apiToken: state.configuration.apiToken,
        triggeredByUserId: widget.activeUser.id,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.title} — ${result.message}')),
      );

      setState(() {
        _future = _loadStatus();
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Référentiel officiel aDRI',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Vérifier',
            icon: Icons.refresh,
            enabled: !_working,
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_OfficialReferentialStateData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done ||
              data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatusCard(data: data),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Référentiel installé sur le serveur',
                      emptyText:
                          'Aucun référentiel officiel n’est encore installé côté serveur.',
                      summary: data.result.current,
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Dernière version détectée chez aDRI',
                      emptyText:
                          'Aucune version distante n’a pu être détectée pour le moment.',
                      summary: data.result.remote,
                    ),
                    const SizedBox(height: 12),
                    _ActionsCard(
                      working: _working,
                      enabled:
                          data.configuration.isConfigured &&
                          data.result.status !=
                              OfficialReferentialApiStatus.unreachable,
                      updateAvailable: data.result.updateAvailable,
                      onRefresh: _refresh,
                      onUpdate: () => _update(data),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OfficialReferentialStateData {
  final SyncConfiguration configuration;
  final OfficialReferentialApiResult result;

  const _OfficialReferentialStateData({
    required this.configuration,
    required this.result,
  });
}

class _StatusCard extends StatelessWidget {
  final _OfficialReferentialStateData data;

  const _StatusCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final result = data.result;
    final colorScheme = Theme.of(context).colorScheme;
    final icon = result.isAvailable
        ? result.updateAvailable
              ? Icons.update_outlined
              : Icons.check_circle_outline
        : Icons.error_outline;
    final statusText = result.isAvailable
        ? result.updateAvailable
              ? 'Mise à jour disponible'
              : 'À jour ou vérifié'
        : 'Vérification impossible';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 38),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(result.title),
                  const SizedBox(height: 4),
                  Text(
                    result.message,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Tenant ${result.tenantId}')),
                      Chip(
                        label: Text(data.configuration.authorizationModeLabel),
                      ),
                      if (result.statusCode != null)
                        Chip(label: Text('HTTP ${result.statusCode}')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String emptyText;
  final OfficialReferentialSummary? summary;

  const _SummaryCard({
    required this.title,
    required this.emptyText,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final item = summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (item == null || !item.exists)
              Text(emptyText)
            else ...[
              _InfoLine(label: 'Version', value: item.version),
              _InfoLine(label: 'Fichier', value: item.filePath),
              if (item.pillarCount > 0)
                _InfoLine(label: 'Piliers', value: item.pillarCount.toString()),
              if (item.criterionCount > 0)
                _InfoLine(
                  label: 'Critères',
                  value: item.criterionCount.toString(),
                ),
              if (item.validationStatus.isNotEmpty)
                _InfoLine(label: 'Validation', value: item.validationStatus),
              if (item.shortBlobId.isNotEmpty)
                _InfoLine(label: 'Blob GitLab', value: item.shortBlobId),
              if (item.sourceSha256.isNotEmpty)
                _InfoLine(label: 'SHA-256 source', value: item.sourceSha256),
              if (item.importedAt != null)
                _InfoLine(
                  label: 'Import serveur',
                  value: _formatDateTime(item.importedAt!),
                ),
              if (item.webUrl.isNotEmpty)
                SelectableText('GitLab : ${item.webUrl}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final bool working;
  final bool enabled;
  final bool updateAvailable;
  final Future<void> Function() onRefresh;
  final VoidCallback onUpdate;

  const _ActionsCard({
    required this.working,
    required this.enabled,
    required this.updateAvailable,
    required this.onRefresh,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 680;
    final buttons = [
      OutlinedButton.icon(
        onPressed: working ? null : onRefresh,
        icon: const Icon(Icons.search_outlined),
        label: const Text('Vérifier'),
      ),
      FilledButton.icon(
        onPressed: working || !enabled ? null : onUpdate,
        icon: const Icon(Icons.download_outlined),
        label: Text(updateAvailable ? 'Mettre à jour' : 'Réinstaller'),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'La mise à jour télécharge le fichier officiel depuis GitLab, le convertit en JSON canonique, le valide et l’installe dans la base serveur OpenIRN.',
            ),
            const SizedBox(height: 14),
            if (isNarrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final button in buttons) ...[
                    button,
                    const SizedBox(height: 8),
                  ],
                ],
              )
            else
              Wrap(spacing: 10, runSpacing: 10, children: buttons),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
