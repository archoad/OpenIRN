import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class ServerMaintenanceScreen extends StatefulWidget {
  final AppUser activeUser;

  const ServerMaintenanceScreen({required this.activeUser, super.key});

  @override
  State<ServerMaintenanceScreen> createState() =>
      _ServerMaintenanceScreenState();
}

class _ServerMaintenanceScreenState extends State<ServerMaintenanceScreen> {
  final _accessPolicy = const AccessPolicyService();
  final _configurationRepository = const LocalSyncConfigurationRepository();

  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isDeleting = false;
  String? _errorMessage;
  String? _successMessage;
  SyncConfiguration? _configuration;
  _MaintenanceStatus? _status;

  bool get _canManage =>
      _accessPolicy.canManageServerMaintenance(widget.activeUser);
  bool get _isWorking => _isBackingUp || _isRestoring || _isDeleting;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!_canManage) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Cette page est réservée aux administrateurs.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final configuration = await _configurationRepository.loadConfiguration();
      if (!configuration.isConfigured) {
        if (!mounted) {
          return;
        }
        setState(() {
          _configuration = configuration;
          _isLoading = false;
          _errorMessage =
              'La synchronisation serveur n’est pas configurée sur ce terminal.';
        });
        return;
      }

      final body = await _getJson(
        configuration,
        '/maintenance/status',
        <String, String>{'limit': '20', 'tenantId': configuration.tenantId},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _configuration = configuration;
        _status = _MaintenanceStatus.fromJson(body);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger la maintenance serveur : $error';
      });
    }
  }

  Future<void> _runBackup() async {
    final configuration = _configuration;
    if (configuration == null || !configuration.isConfigured || _isWorking) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Créer une sauvegarde serveur ?'),
        content: const ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            'OpenIRN va demander au serveur de créer une sauvegarde SQLite cohérente. '
            'Le serveur reste disponible pendant l’opération.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isBackingUp = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final body = await _postJson(
        configuration,
        '/maintenance/backup',
        <String, dynamic>{
          'tenantId': configuration.tenantId,
          'triggeredByUserId': widget.activeUser.id,
        },
      );
      if (!mounted) {
        return;
      }
      final maintenance = _jsonObject(body['maintenance']);
      final backup = _jsonObject(body['backup']);
      setState(() {
        _status = maintenance == null
            ? _status
            : _MaintenanceStatus.fromJson(maintenance);
        _isBackingUp = false;
        _successMessage = backup == null
            ? 'Sauvegarde serveur créée.'
            : 'Sauvegarde créée : ${backup['name'] ?? backup['backupDb'] ?? 'OK'}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBackingUp = false;
        _errorMessage = 'Impossible de créer la sauvegarde : $error';
      });
    }
  }

  Future<void> _restoreBackup(_BackupEntry backup) async {
    final configuration = _configuration;
    if (configuration == null || !configuration.isConfigured || _isWorking) {
      return;
    }

    final firstConfirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Restaurer cette sauvegarde ?'),
        content: ResponsiveDialogContent(
          maxWidth: 680,
          child: Text(
            'Cette opération remplacera la base SQLite serveur actuelle par :\n\n'
            '${backup.name}\n\n'
            'Une sauvegarde de sécurité sera créée automatiquement avant restauration.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.restore_outlined),
            label: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (firstConfirmation != true || !mounted) {
      return;
    }

    final controller = TextEditingController();
    final finalConfirmation = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Confirmation finale'),
        content: ResponsiveDialogContent(
          maxWidth: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tape RESTAURER pour confirmer la restauration serveur.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: shouldAutofocusTextField(context),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Confirmation',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.of(
                  context,
                ).pop(controller.text.trim() == 'RESTAURER'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pop(controller.text.trim() == 'RESTAURER'),
            icon: const Icon(Icons.restore_outlined),
            label: const Text('Restaurer'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (finalConfirmation != true) {
      return;
    }

    setState(() {
      _isRestoring = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final encodedBackupName = Uri.encodeComponent(backup.name);
      final body = await _postJson(
        configuration,
        '/maintenance/backups/$encodedBackupName/restore',
        <String, dynamic>{
          'tenantId': configuration.tenantId,
          'triggeredByUserId': widget.activeUser.id,
        },
      );
      if (!mounted) {
        return;
      }
      final maintenance = _jsonObject(body['maintenance']);
      setState(() {
        _status = maintenance == null
            ? _status
            : _MaintenanceStatus.fromJson(maintenance);
        _isRestoring = false;
        _successMessage = 'Sauvegarde restaurée : ${backup.name}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRestoring = false;
        _errorMessage = 'Impossible de restaurer la sauvegarde : $error';
      });
    }
  }

  Future<void> _deleteBackup(_BackupEntry backup) async {
    final configuration = _configuration;
    if (configuration == null || !configuration.isConfigured || _isWorking) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Supprimer cette sauvegarde ?'),
        content: ResponsiveDialogContent(
          maxWidth: 620,
          child: Text(
            'La sauvegarde suivante sera supprimée définitivement du serveur :\n\n${backup.name}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final encodedBackupName = Uri.encodeComponent(backup.name);
      final body = await _deleteJson(
        configuration,
        '/maintenance/backups/$encodedBackupName?tenantId=${Uri.encodeQueryComponent(configuration.tenantId)}',
      );
      if (!mounted) {
        return;
      }
      final maintenance = _jsonObject(body['maintenance']);
      setState(() {
        _status = maintenance == null
            ? _status
            : _MaintenanceStatus.fromJson(maintenance);
        _isDeleting = false;
        _successMessage = 'Sauvegarde supprimée : ${backup.name}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeleting = false;
        _errorMessage = 'Impossible de supprimer la sauvegarde : $error';
      });
    }
  }

  Future<Map<String, dynamic>> _getJson(
    SyncConfiguration configuration,
    String path,
    Map<String, String> parameters,
  ) async {
    final uri = Uri.parse(
      '${configuration.apiBaseUrl}$path',
    ).replace(queryParameters: parameters);
    return _requestJson(configuration, uri, method: 'GET');
  }

  Future<Map<String, dynamic>> _postJson(
    SyncConfiguration configuration,
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('${configuration.apiBaseUrl}$path');
    return _requestJson(configuration, uri, method: 'POST', payload: payload);
  }

  Future<Map<String, dynamic>> _deleteJson(
    SyncConfiguration configuration,
    String path,
  ) async {
    final uri = Uri.parse('${configuration.apiBaseUrl}$path');
    return _requestJson(configuration, uri, method: 'DELETE');
  }

  Future<Map<String, dynamic>> _requestJson(
    SyncConfiguration configuration,
    Uri uri, {
    required String method,
    Map<String, dynamic>? payload,
  }) async {
    final client = HttpClient();
    try {
      final HttpClientRequest request;
      if (method == 'POST') {
        request = await client.postUrl(uri);
      } else if (method == 'DELETE') {
        request = await client.deleteUrl(uri);
      } else {
        request = await client.getUrl(uri);
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${configuration.apiToken}',
      );
      if (payload != null) {
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        request.add(utf8.encode(jsonEncode(payload)));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      final decoded = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (decoded is Map && decoded['detail'] != null) {
          throw HttpException(decoded['detail'].toString(), uri: uri);
        }
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw const FormatException('Réponse JSON inattendue.');
    } on TimeoutException {
      throw TimeoutException(
        'Le serveur n’a pas répondu dans le délai attendu.',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuration = _configuration;
    final status = _status;

    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Maintenance serveur',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Actualiser',
            icon: Icons.refresh,
            enabled: !_isLoading && !_isWorking,
            onSelected: _loadStatus,
          ),
          OpenIrnAppBarAction(
            id: 'backup',
            label: 'Sauvegarder maintenant',
            icon: Icons.backup_outlined,
            enabled: status != null && !_isWorking,
            onSelected: _runBackup,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isLoading) const LinearProgressIndicator(),
              if (_isLoading) const SizedBox(height: 12),
              if (_isWorking) const LinearProgressIndicator(),
              if (_isWorking) const SizedBox(height: 12),
              if (_errorMessage != null) ...[
                _StatusBanner(
                  icon: Icons.error_outline,
                  text: _errorMessage!,
                  isError: true,
                ),
                const SizedBox(height: 12),
              ],
              if (_successMessage != null) ...[
                _StatusBanner(
                  icon: Icons.check_circle_outline,
                  text: _successMessage!,
                  isError: false,
                ),
                const SizedBox(height: 12),
              ],
              _ServerConfigurationCard(configuration: configuration),
              const SizedBox(height: 12),
              if (status != null) ...[
                _DatabaseCard(database: status.database),
                const SizedBox(height: 12),
                _BackupCard(
                  backup: status.backup,
                  isBackingUp: _isBackingUp,
                  onBackup: _runBackup,
                ),
                const SizedBox(height: 12),
                _BackupListCard(
                  backups: status.backup.backups,
                  isWorking: _isWorking,
                  onRestore: _restoreBackup,
                  onDelete: _deleteBackup,
                ),
                const SizedBox(height: 12),
                _BackupAuditCard(events: status.backup.auditEvents),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerConfigurationCard extends StatelessWidget {
  final SyncConfiguration? configuration;

  const _ServerConfigurationCard({required this.configuration});

  @override
  Widget build(BuildContext context) {
    final configuration = this.configuration;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Serveur',
              value:
                  configuration?.apiBaseUrl ??
                  SyncConfiguration.fixedApiBaseUrl,
            ),
            _InfoRow(
              label: 'Espace de travail',
              value:
                  configuration?.tenantId ?? SyncConfiguration.defaultTenantId,
            ),
            _InfoRow(
              label: 'Clé d’accès',
              value: configuration?.hasApiToken == true
                  ? configuration!.maskedApiToken
                  : 'Non configuré',
            ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseCard extends StatelessWidget {
  final _MaintenanceDatabase database;

  const _DatabaseCard({required this.database});

  @override
  Widget build(BuildContext context) {
    final ok = database.integrityCheck == 'ok';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.verified_outlined : Icons.warning_amber_outlined,
                  color: ok
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Base SQLite',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'Intégrité', value: database.integrityCheck),
            _InfoRow(
              label: 'Taille DB',
              value: _formatBytes(database.sizeBytes),
            ),
            _InfoRow(label: 'WAL', value: _formatBytes(database.walSizeBytes)),
            _InfoRow(label: 'Chemin', value: database.path),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: database.counts.entries
                  .map(
                    (entry) => Chip(
                      label: Text('${entry.key} : ${entry.value ?? '-'}'),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  final _MaintenanceBackup backup;
  final bool isBackingUp;
  final VoidCallback onBackup;

  const _BackupCard({
    required this.backup,
    required this.isBackingUp,
    required this.onBackup,
  });

  @override
  Widget build(BuildContext context) {
    final latest = backup.latest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sauvegardes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _InfoRow(label: 'Répertoire', value: backup.directory),
            _InfoRow(label: 'Nombre', value: backup.count.toString()),
            _InfoRow(label: 'Rétention', value: '${backup.keep} sauvegardes'),
            _InfoRow(
              label: 'Automatique',
              value: backup.security.autoEnabled ? 'Activée' : 'Désactivée',
            ),
            _InfoRow(
              label: 'Protection',
              value: backup.security.protectiveEnabled
                  ? 'Avant opérations sensibles'
                  : 'Désactivée',
            ),
            _InfoRow(
              label: 'Signature',
              value: backup.security.signatureSecretConfigured
                  ? 'HMAC active'
                  : 'Clé non configurée',
            ),
            if (backup.security.unsignedVisibleBackups > 0)
              _InfoRow(
                label: 'À vérifier',
                value:
                    '${backup.security.unsignedVisibleBackups} sauvegarde(s) non signée(s) ou non vérifiées',
              ),
            if (latest != null) ...[
              const Divider(height: 24),
              _InfoRow(label: 'Dernière sauvegarde', value: latest.name),
              _InfoRow(label: 'Date', value: _formatDate(latest.createdAt)),
              _InfoRow(label: 'Taille', value: _formatBytes(latest.sizeBytes)),
              _InfoRow(
                label: 'SHA-256',
                value: latest.sha256.isEmpty ? 'Non disponible' : latest.sha256,
              ),
              _InfoRow(
                label: 'Signature',
                value: _signatureLabel(latest.signatureStatus),
              ),
              if (latest.reason.isNotEmpty)
                _InfoRow(
                  label: 'Motif',
                  value: _backupReasonLabel(latest.reason),
                ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isBackingUp ? null : onBackup,
                icon: const Icon(Icons.backup_outlined),
                label: Text(
                  isBackingUp
                      ? 'Sauvegarde en cours…'
                      : 'Sauvegarder maintenant',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupListCard extends StatelessWidget {
  final List<_BackupEntry> backups;
  final bool isWorking;
  final ValueChanged<_BackupEntry> onRestore;
  final ValueChanged<_BackupEntry> onDelete;

  const _BackupListCard({
    required this.backups,
    required this.isWorking,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dernières sauvegardes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (backups.isEmpty)
              const Text('Aucune sauvegarde disponible pour le moment.')
            else
              ...backups.map(
                (backup) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(
                    backup.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatDate(backup.createdAt)} • ${_formatBytes(backup.sizeBytes)} • ${_signatureLabel(backup.signatureStatus)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: !isWorking,
                    tooltip: 'Actions sauvegarde',
                    onSelected: (value) {
                      if (value == 'restore') {
                        onRestore(backup);
                      } else if (value == 'delete') {
                        onDelete(backup);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'restore',
                        child: Row(
                          children: [
                            Icon(Icons.restore_outlined),
                            SizedBox(width: 10),
                            Text('Restaurer'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Supprimer',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackupAuditCard extends StatelessWidget {
  final List<_BackupAuditEvent> events;

  const _BackupAuditCard({required this.events});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Journal des sauvegardes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const Text('Aucun événement de sauvegarde enregistré.')
            else
              ...events.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    event.eventType == 'backup.created'
                        ? Icons.backup_outlined
                        : event.eventType == 'backup.restored'
                        ? Icons.restore_outlined
                        : Icons.history_outlined,
                  ),
                  title: Text(
                    event.backupName.isEmpty
                        ? event.eventType
                        : event.backupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatDate(event.createdAt)} • ${_backupReasonLabel(event.reason)}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isError;

  const _StatusBanner({
    required this.icon,
    required this.text,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MaintenanceStatus {
  final _MaintenanceDatabase database;
  final _MaintenanceBackup backup;

  const _MaintenanceStatus({required this.database, required this.backup});

  factory _MaintenanceStatus.fromJson(Map<String, dynamic> json) {
    return _MaintenanceStatus(
      database: _MaintenanceDatabase.fromJson(
        _jsonObject(json['database']) ?? const <String, dynamic>{},
      ),
      backup: _MaintenanceBackup.fromJson(
        _jsonObject(json['backup']) ?? const <String, dynamic>{},
      ),
    );
  }
}

class _MaintenanceDatabase {
  final String path;
  final int sizeBytes;
  final int walSizeBytes;
  final int shmSizeBytes;
  final String integrityCheck;
  final Map<String, int?> counts;

  const _MaintenanceDatabase({
    required this.path,
    required this.sizeBytes,
    required this.walSizeBytes,
    required this.shmSizeBytes,
    required this.integrityCheck,
    required this.counts,
  });

  factory _MaintenanceDatabase.fromJson(Map<String, dynamic> json) {
    final rawCounts = _jsonObject(json['counts']) ?? const <String, dynamic>{};
    return _MaintenanceDatabase(
      path: json['path']?.toString() ?? '',
      sizeBytes: _intFromJson(json['sizeBytes']),
      walSizeBytes: _intFromJson(json['walSizeBytes']),
      shmSizeBytes: _intFromJson(json['shmSizeBytes']),
      integrityCheck: json['integrityCheck']?.toString() ?? 'unknown',
      counts: rawCounts.map(
        (key, value) =>
            MapEntry(key, value == null ? null : _intFromJson(value)),
      ),
    );
  }
}

class _MaintenanceBackup {
  final String directory;
  final int keep;
  final int count;
  final _BackupEntry? latest;
  final List<_BackupEntry> backups;
  final _BackupSecurity security;
  final List<_BackupAuditEvent> auditEvents;

  const _MaintenanceBackup({
    required this.directory,
    required this.keep,
    required this.count,
    required this.latest,
    required this.backups,
    required this.security,
    required this.auditEvents,
  });

  factory _MaintenanceBackup.fromJson(Map<String, dynamic> json) {
    final rawLatest = _jsonObject(json['latest']);
    return _MaintenanceBackup(
      directory: json['directory']?.toString() ?? '',
      keep: _intFromJson(json['keep']),
      count: _intFromJson(json['count']),
      latest: rawLatest == null ? null : _BackupEntry.fromJson(rawLatest),
      backups: _jsonList(
        json['backups'],
      ).map(_BackupEntry.fromJson).toList(growable: false),
      security: _BackupSecurity.fromJson(
        _jsonObject(json['security']) ?? const <String, dynamic>{},
      ),
      auditEvents: _jsonList(
        json['auditEvents'],
      ).map(_BackupAuditEvent.fromJson).toList(growable: false),
    );
  }
}

class _BackupSecurity {
  final bool autoEnabled;
  final bool protectiveEnabled;
  final int protectiveMinIntervalMinutes;
  final bool signatureSecretConfigured;
  final int unsignedVisibleBackups;

  const _BackupSecurity({
    required this.autoEnabled,
    required this.protectiveEnabled,
    required this.protectiveMinIntervalMinutes,
    required this.signatureSecretConfigured,
    required this.unsignedVisibleBackups,
  });

  factory _BackupSecurity.fromJson(Map<String, dynamic> json) {
    return _BackupSecurity(
      autoEnabled: json['autoEnabled'] != false,
      protectiveEnabled: json['protectiveEnabled'] != false,
      protectiveMinIntervalMinutes: _intFromJson(
        json['protectiveMinIntervalMinutes'],
      ),
      signatureSecretConfigured: json['signatureSecretConfigured'] == true,
      unsignedVisibleBackups: _intFromJson(json['unsignedVisibleBackups']),
    );
  }
}

class _BackupEntry {
  final String name;
  final DateTime? createdAt;
  final int sizeBytes;
  final String sha256;
  final String signatureStatus;
  final String reason;
  final bool automatic;

  const _BackupEntry({
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.sha256,
    required this.signatureStatus,
    required this.reason,
    required this.automatic,
  });

  factory _BackupEntry.fromJson(Map<String, dynamic> json) {
    return _BackupEntry(
      name: json['name']?.toString() ?? '',
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toLocal(),
      sizeBytes: _intFromJson(json['sizeBytes']),
      sha256: json['sha256']?.toString() ?? '',
      signatureStatus: json['signatureStatus']?.toString() ?? 'unsigned',
      reason: json['reason']?.toString() ?? '',
      automatic: json['automatic'] == true,
    );
  }
}

class _BackupAuditEvent {
  final String backupName;
  final String eventType;
  final String reason;
  final String triggeredByUserId;
  final DateTime? createdAt;

  const _BackupAuditEvent({
    required this.backupName,
    required this.eventType,
    required this.reason,
    required this.triggeredByUserId,
    required this.createdAt,
  });

  factory _BackupAuditEvent.fromJson(Map<String, dynamic> json) {
    return _BackupAuditEvent(
      backupName: json['backupName']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      triggeredByUserId: json['triggeredByUserId']?.toString() ?? '',
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

Map<String, dynamic>? _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

List<Map<String, dynamic>> _jsonList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

int _intFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _signatureLabel(String status) {
  switch (status) {
    case 'valid':
      return 'Signature valide';
    case 'invalid':
      return 'Signature invalide';
    case 'unverified_no_secret':
      return 'Clé absente';
    case 'unsigned':
      return 'Non signée';
    default:
      return status.isEmpty ? 'Non disponible' : status;
  }
}

String _backupReasonLabel(String reason) {
  switch (reason) {
    case 'manual':
      return 'Manuelle';
    case 'scheduled_timer':
      return 'Automatique planifiée';
    case 'pre_restore_safety':
      return 'Sécurité avant restauration';
    case 'pre_official_referential_update':
      return 'Avant mise à jour référentiel';
    case 'pre_users_replace':
      return 'Avant remplacement utilisateurs';
    case 'pre_user_pin_change':
      return 'Avant changement PIN';
    case 'pre_campaign_restore':
      return 'Avant restauration campagne';
    case 'manual_restore':
      return 'Restauration manuelle';
    case 'manual_delete':
      return 'Suppression manuelle';
    default:
      return reason.isEmpty ? 'Non renseigné' : reason;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes o';
  }
  final units = ['Ko', 'Mo', 'Go', 'To'];
  var value = bytes / 1024.0;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024.0;
    unitIndex += 1;
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'Non disponible';
  }
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
