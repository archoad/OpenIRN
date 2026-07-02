import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/repositories/local_sync_configuration_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/sync_configuration.dart';
import '../../domain/services/access_policy_service.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_dialog.dart';

class CampaignHistoryScreen extends StatefulWidget {
  final AppUser activeUser;
  final String? initialCampaignId;
  final String? initialCampaignName;

  const CampaignHistoryScreen({
    required this.activeUser,
    this.initialCampaignId,
    this.initialCampaignName,
    super.key,
  });

  @override
  State<CampaignHistoryScreen> createState() => _CampaignHistoryScreenState();
}

class _CampaignHistoryScreenState extends State<CampaignHistoryScreen> {
  final _accessPolicy = const AccessPolicyService();
  final _configurationRepository = const LocalSyncConfigurationRepository();

  bool _isLoading = true;
  bool _isLoadingRevisionPayload = false;
  bool _isRestoringRevision = false;
  String? _errorMessage;
  SyncConfiguration? _configuration;
  _CampaignServerSummary? _summary;
  List<_ServerCampaign> _campaigns = const <_ServerCampaign>[];
  List<_CampaignRevision> _revisions = const <_CampaignRevision>[];
  List<_CampaignRevision> _conflicts = const <_CampaignRevision>[];
  String? _selectedCampaignId;

  bool get _canView => _accessPolicy.canViewCampaignHistory(widget.activeUser);

  bool get _canRestore =>
      _accessPolicy.canRestoreCampaignRevision(widget.activeUser);

  @override
  void initState() {
    super.initState();
    _selectedCampaignId = widget.initialCampaignId;
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!_canView) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Cette page est réservée aux administrateurs et pilotes IRN.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final configuration = await _configurationRepository.loadConfiguration();
      if (!configuration.isConfigured) {
        setState(() {
          _configuration = configuration;
          _isLoading = false;
          _errorMessage =
              'La synchronisation serveur n’est pas configurée sur ce terminal.';
        });
        return;
      }

      final campaignsBody = await _getJson(
        configuration,
        '/campaigns',
        <String, String>{'tenantId': configuration.tenantId, 'limit': '200'},
      );
      final summary = _CampaignServerSummary.fromJson(campaignsBody);
      final campaigns = _jsonList(campaignsBody['campaigns'])
          .map(_ServerCampaign.fromJson)
          .where((campaign) => campaign.campaignId.isNotEmpty)
          .toList(growable: false);

      final preferredCampaignId = _selectedCampaignId?.trim().isNotEmpty == true
          ? _selectedCampaignId!.trim()
          : widget.initialCampaignId?.trim();
      final selectedCampaignId =
          campaigns.any(
            (campaign) => campaign.campaignId == preferredCampaignId,
          )
          ? preferredCampaignId
          : campaigns.isNotEmpty
          ? campaigns.first.campaignId
          : null;

      List<_CampaignRevision> revisions = const <_CampaignRevision>[];
      List<_CampaignRevision> conflicts = const <_CampaignRevision>[];
      if (selectedCampaignId != null && selectedCampaignId.isNotEmpty) {
        revisions = await _loadRevisions(configuration, selectedCampaignId);
        conflicts = await _loadConflicts(configuration, selectedCampaignId);
      } else {
        conflicts = await _loadConflicts(configuration, null);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _configuration = configuration;
        _summary = summary;
        _campaigns = campaigns;
        _selectedCampaignId = selectedCampaignId;
        _revisions = revisions;
        _conflicts = conflicts;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger l’historique serveur : $error';
      });
    }
  }

  Future<void> _selectCampaign(String? campaignId) async {
    if (campaignId == null ||
        campaignId.trim().isEmpty ||
        campaignId == _selectedCampaignId) {
      return;
    }
    setState(() {
      _selectedCampaignId = campaignId;
      _isLoading = true;
      _errorMessage = null;
    });
    await _loadAll();
  }

  Future<List<_CampaignRevision>> _loadRevisions(
    SyncConfiguration configuration,
    String campaignId,
  ) async {
    final body = await _getJson(
      configuration,
      '/campaigns/revisions',
      <String, String>{
        'tenantId': configuration.tenantId,
        'campaignId': campaignId,
        'limit': '80',
      },
    );
    return _jsonList(
      body['revisions'],
    ).map(_CampaignRevision.fromJson).toList(growable: false);
  }

  Future<List<_CampaignRevision>> _loadConflicts(
    SyncConfiguration configuration,
    String? campaignId,
  ) async {
    final parameters = <String, String>{
      'tenantId': configuration.tenantId,
      'limit': '80',
    };
    if (campaignId != null && campaignId.trim().isNotEmpty) {
      parameters['campaignId'] = campaignId.trim();
    }
    final body = await _getJson(
      configuration,
      '/campaigns/conflicts',
      parameters,
    );
    return _jsonList(
      body['conflicts'],
    ).map(_CampaignRevision.fromJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> _loadRevisionPayload(
    SyncConfiguration configuration,
    _CampaignRevision revision,
  ) async {
    final body =
        await _getJson(configuration, '/campaigns/revision', <String, String>{
          'tenantId': configuration.tenantId,
          'campaignId': revision.campaignId,
          'serverRevision': revision.serverRevision.toString(),
        });
    final revisionBody = _jsonObject(body['revision']);
    return _jsonObject(revisionBody?['payload']) ?? <String, dynamic>{};
  }

  Future<void> _openRevisionPayload(_CampaignRevision revision) async {
    final configuration = _configuration;
    if (configuration == null) {
      return;
    }
    setState(() {
      _isLoadingRevisionPayload = true;
    });
    try {
      final currentPayload = await _loadRevisionPayload(
        configuration,
        revision,
      );

      if (revision.conflictDetected && revision.serverRevision > 1) {
        final previousRevision = revision.copyWith(
          serverRevision: revision.serverRevision - 1,
        );
        final previousPayload = await _loadRevisionPayload(
          configuration,
          previousRevision,
        );
        final impacts = _buildPayloadImpacts(previousPayload, currentPayload);

        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            insetPadding: responsiveDialogInsetPadding(context),
            title: Text(
              'Impact du conflit — révision ${revision.serverRevision}',
            ),
            content: ResponsiveDialogContent(
              maxWidth: 920,
              child: SingleChildScrollView(
                child: _ConflictImpactView(
                  revision: revision,
                  comparedRevision: revision.serverRevision - 1,
                  impacts: impacts,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
        );
        return;
      }

      final formatted = const JsonEncoder.withIndent(
        '  ',
      ).convert(currentPayload);

      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          insetPadding: responsiveDialogInsetPadding(context),
          title: Text('Révision serveur ${revision.serverRevision}'),
          content: ResponsiveDialogContent(
            maxWidth: 920,
            child: SingleChildScrollView(
              child: SelectableText(
                formatted,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de charger le détail de la révision : $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRevisionPayload = false;
        });
      }
    }
  }

  Future<void> _restoreRevision(_CampaignRevision revision) async {
    final configuration = _configuration;
    if (!_canRestore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La restauration d’une révision est réservée aux administrateurs et pilotes IRN.',
          ),
        ),
      );
      return;
    }
    if (configuration == null || _isRestoringRevision) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Restaurer cette révision ?'),
        content: ResponsiveDialogContent(
          maxWidth: 680,
          child: Text(
            'La révision serveur ${revision.serverRevision} de la campagne "${revision.campaignName}" deviendra la version courante. '
            'Une nouvelle révision serveur sera créée et les terminaux connectés recevront automatiquement la mise à jour.',
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
            label: const Text('Restaurer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isRestoringRevision = true;
    });

    try {
      final body = await _postJson(
        configuration,
        '/campaigns/restore',
        <String, dynamic>{
          'tenantId': configuration.tenantId,
          'campaignId': revision.campaignId,
          'serverRevision': revision.serverRevision,
          'restoredByUserId': widget.activeUser.id,
          'reason': 'restore_from_openirn_admin_ui',
        },
      );

      if (!mounted) {
        return;
      }
      final status = body['status']?.toString() ?? 'accepted';
      final newRevision = body['serverRevision']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'no_change'
                ? 'Cette révision est déjà la version courante.'
                : 'Révision restaurée. Nouvelle révision serveur : ${newRevision ?? '—'}',
          ),
        ),
      );
      await _loadAll();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de restaurer la révision : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringRevision = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _getJson(
    SyncConfiguration configuration,
    String path,
    Map<String, String> queryParameters,
  ) async {
    final baseUrl = SyncConfiguration.normalizeApiBaseUrl(
      configuration.apiBaseUrl,
    );
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: queryParameters);
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${configuration.apiToken}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(body);
      final decodedBody = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode} — ${decodedBody['detail'] ?? body}',
        );
      }
      return decodedBody;
    } on TimeoutException {
      throw const HttpException('délai dépassé');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    SyncConfiguration configuration,
    String path,
    Map<String, dynamic> payload,
  ) async {
    final baseUrl = SyncConfiguration.normalizeApiBaseUrl(
      configuration.apiBaseUrl,
    );
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'OpenIRN');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${configuration.apiToken}',
      );
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(body);
      final decodedBody = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode} — ${decodedBody['detail'] ?? body}',
        );
      }
      return decodedBody;
    } on TimeoutException {
      throw const HttpException('délai dépassé');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Historique / conflits',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Actualiser',
            icon: Icons.refresh,
            enabled: !_isLoading,
            onSelected: _loadAll,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MessageCard(
            icon: Icons.warning_amber_outlined,
            title: 'Historique indisponible',
            message: _errorMessage!,
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ServerSummaryCard(summary: _summary, configuration: _configuration),
          const SizedBox(height: 12),
          _CampaignSelectorCard(
            campaigns: _campaigns,
            selectedCampaignId: _selectedCampaignId,
            onChanged: _selectCampaign,
          ),
          const SizedBox(height: 12),
          _ConflictSection(
            conflicts: _conflicts,
            onOpenPayload: _openRevisionPayload,
            onRestoreRevision: _restoreRevision,
            isLoadingPayload: _isLoadingRevisionPayload,
            isRestoringRevision: _isRestoringRevision,
          ),
          const SizedBox(height: 12),
          _RevisionSection(
            revisions: _revisions,
            onOpenPayload: _openRevisionPayload,
            onRestoreRevision: _restoreRevision,
            isLoadingPayload: _isLoadingRevisionPayload,
            isRestoringRevision: _isRestoringRevision,
          ),
        ],
      ),
    );
  }
}

class _ServerSummaryCard extends StatelessWidget {
  final _CampaignServerSummary? summary;
  final SyncConfiguration? configuration;

  const _ServerSummaryCard({
    required this.summary,
    required this.configuration,
  });

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final configuration = this.configuration;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'État serveur SQLite',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Espace de travail : ${configuration?.tenantId ?? '—'}'),
            Text('Serveur : ${configuration?.apiBaseUrl ?? '—'}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: 'Campagnes',
                  value: '${summary?.campaignCount ?? 0}',
                ),
                _MetricChip(
                  label: 'Révisions',
                  value: '${summary?.revisionCount ?? 0}',
                ),
                _MetricChip(
                  label: 'Conflits',
                  value: '${summary?.conflictCount ?? 0}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignSelectorCard extends StatelessWidget {
  final List<_ServerCampaign> campaigns;
  final String? selectedCampaignId;
  final ValueChanged<String?> onChanged;

  const _CampaignSelectorCard({
    required this.campaigns,
    required this.selectedCampaignId,
    required this.onChanged,
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
              'Campagne serveur',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (campaigns.isEmpty)
              const Text('Aucune campagne trouvée côté serveur.')
            else
              DropdownButtonFormField<String>(
                initialValue: selectedCampaignId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Campagne',
                ),
                items: campaigns
                    .map(
                      (campaign) => DropdownMenuItem<String>(
                        value: campaign.campaignId,
                        child: Text(
                          '${campaign.campaignName} — rév. ${campaign.serverRevision}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _ConflictSection extends StatelessWidget {
  final List<_CampaignRevision> conflicts;
  final ValueChanged<_CampaignRevision> onOpenPayload;
  final ValueChanged<_CampaignRevision> onRestoreRevision;
  final bool isLoadingPayload;
  final bool isRestoringRevision;

  const _ConflictSection({
    required this.conflicts,
    required this.onOpenPayload,
    required this.onRestoreRevision,
    required this.isLoadingPayload,
    required this.isRestoringRevision,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Conflits détectés',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text('${conflicts.length}')),
              ],
            ),
            const SizedBox(height: 8),
            if (conflicts.isEmpty)
              const Text('Aucun conflit détecté pour cette campagne.')
            else
              ...conflicts.map(
                (revision) => _RevisionTile(
                  revision: revision,
                  onOpenPayload: onOpenPayload,
                  onRestoreRevision: onRestoreRevision,
                  isLoadingPayload: isLoadingPayload,
                  isRestoringRevision: isRestoringRevision,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RevisionSection extends StatelessWidget {
  final List<_CampaignRevision> revisions;
  final ValueChanged<_CampaignRevision> onOpenPayload;
  final ValueChanged<_CampaignRevision> onRestoreRevision;
  final bool isLoadingPayload;
  final bool isRestoringRevision;

  const _RevisionSection({
    required this.revisions,
    required this.onOpenPayload,
    required this.onRestoreRevision,
    required this.isLoadingPayload,
    required this.isRestoringRevision,
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
              'Historique des révisions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (revisions.isEmpty)
              const Text('Aucune révision disponible pour cette campagne.')
            else
              ...revisions.map(
                (revision) => _RevisionTile(
                  revision: revision,
                  onOpenPayload: onOpenPayload,
                  onRestoreRevision: onRestoreRevision,
                  isLoadingPayload: isLoadingPayload,
                  isRestoringRevision: isRestoringRevision,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RevisionTile extends StatelessWidget {
  final _CampaignRevision revision;
  final ValueChanged<_CampaignRevision> onOpenPayload;
  final ValueChanged<_CampaignRevision> onRestoreRevision;
  final bool isLoadingPayload;
  final bool isRestoringRevision;

  const _RevisionTile({
    required this.revision,
    required this.onOpenPayload,
    required this.onRestoreRevision,
    required this.isLoadingPayload,
    required this.isRestoringRevision,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Révision ${revision.serverRevision} — ${revision.campaignName}',
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text('Terminal : ${revision.deviceId}'),
                  Text('Reçue : ${revision.receivedAt ?? '—'}'),
                  Text('Checksum : ${revision.shortChecksum}'),
                  if (revision.conflictDetected)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Conflit : ${revision.conflictReason.isEmpty ? 'last_write_wins' : revision.conflictReason}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
              final buttons = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isLoadingPayload
                        ? null
                        : () => onOpenPayload(revision),
                    icon: const Icon(Icons.data_object_outlined),
                    label: Text(
                      revision.conflictDetected ? 'Impact' : 'Payload',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isRestoringRevision
                        ? null
                        : () => onRestoreRevision(revision),
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Restaurer'),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [details, const SizedBox(height: 8), buttons],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  buttons,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label : $value'));
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _CampaignServerSummary {
  final int campaignCount;
  final int revisionCount;
  final int conflictCount;

  const _CampaignServerSummary({
    required this.campaignCount,
    required this.revisionCount,
    required this.conflictCount,
  });

  factory _CampaignServerSummary.fromJson(Map<String, dynamic> json) {
    return _CampaignServerSummary(
      campaignCount: _intFromJson(json['campaignCount']),
      revisionCount: _intFromJson(json['revisionCount']),
      conflictCount: _intFromJson(json['conflictCount']),
    );
  }
}

class _ServerCampaign {
  final String campaignId;
  final String campaignName;
  final int serverRevision;

  const _ServerCampaign({
    required this.campaignId,
    required this.campaignName,
    required this.serverRevision,
  });

  factory _ServerCampaign.fromJson(Map<String, dynamic> json) {
    final campaignId = json['campaignId']?.toString() ?? '';
    return _ServerCampaign(
      campaignId: campaignId,
      campaignName: json['campaignName']?.toString().trim().isNotEmpty == true
          ? json['campaignName'].toString().trim()
          : campaignId,
      serverRevision: _intFromJson(json['serverRevision']),
    );
  }
}

class _CampaignRevision {
  final String campaignId;
  final String campaignName;
  final int serverRevision;
  final String serverSyncId;
  final String deviceId;
  final String? receivedAt;
  final String payloadSha256;
  final bool conflictDetected;
  final String conflictReason;

  const _CampaignRevision({
    required this.campaignId,
    required this.campaignName,
    required this.serverRevision,
    required this.serverSyncId,
    required this.deviceId,
    required this.receivedAt,
    required this.payloadSha256,
    required this.conflictDetected,
    required this.conflictReason,
  });

  String get shortChecksum {
    if (payloadSha256.length <= 16) {
      return payloadSha256.isEmpty ? '—' : payloadSha256;
    }
    return '${payloadSha256.substring(0, 12)}…${payloadSha256.substring(payloadSha256.length - 6)}';
  }

  _CampaignRevision copyWith({int? serverRevision}) {
    return _CampaignRevision(
      campaignId: campaignId,
      campaignName: campaignName,
      serverRevision: serverRevision ?? this.serverRevision,
      serverSyncId: serverSyncId,
      deviceId: deviceId,
      receivedAt: receivedAt,
      payloadSha256: payloadSha256,
      conflictDetected: conflictDetected,
      conflictReason: conflictReason,
    );
  }

  factory _CampaignRevision.fromJson(Map<String, dynamic> json) {
    final campaignId = json['campaignId']?.toString() ?? '';
    return _CampaignRevision(
      campaignId: campaignId,
      campaignName: json['campaignName']?.toString().trim().isNotEmpty == true
          ? json['campaignName'].toString().trim()
          : campaignId,
      serverRevision: _intFromJson(json['serverRevision']),
      serverSyncId: json['serverSyncId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      receivedAt: json['receivedAt']?.toString(),
      payloadSha256: json['payloadSha256']?.toString() ?? '',
      conflictDetected: json['conflictDetected'] is bool
          ? json['conflictDetected'] as bool
          : false,
      conflictReason: json['conflictReason']?.toString() ?? '',
    );
  }
}

class _ConflictImpactView extends StatelessWidget {
  final _CampaignRevision revision;
  final int comparedRevision;
  final List<_PayloadImpact> impacts;

  const _ConflictImpactView({
    required this.revision,
    required this.comparedRevision,
    required this.impacts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Comparaison entre la révision $comparedRevision et la révision ${revision.serverRevision}.',
        ),
        const SizedBox(height: 8),
        Text('Campagne : ${revision.campaignName}'),
        Text('Terminal source : ${revision.deviceId}'),
        Text(
          'Règle appliquée : ${revision.conflictReason.isEmpty ? 'last_write_wins' : revision.conflictReason}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 16),
        if (impacts.isEmpty)
          const _MessageCard(
            icon: Icons.info_outline,
            title: 'Aucune valeur métier différente détectée',
            message:
                'La révision est marquée en conflit côté serveur, mais les champs métier comparés ne présentent pas de différence exploitable. Les différences peuvent concerner uniquement des métadonnées ou le journal technique.',
          )
        else
          ...impacts.map((impact) => _PayloadImpactTile(impact: impact)),
      ],
    );
  }
}

class _PayloadImpactTile extends StatelessWidget {
  final _PayloadImpact impact;

  const _PayloadImpactTile({required this.impact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              impact.path,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final before = _ImpactValueCard(
                  title: 'Avant',
                  value: impact.beforeLabel,
                );
                final after = _ImpactValueCard(
                  title: 'Après',
                  value: impact.afterLabel,
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [before, const SizedBox(height: 8), after],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: before),
                    const SizedBox(width: 8),
                    Expanded(child: after),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactValueCard extends StatelessWidget {
  final String title;
  final String value;

  const _ImpactValueCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayloadImpact {
  final String path;
  final Object? before;
  final Object? after;

  const _PayloadImpact({
    required this.path,
    required this.before,
    required this.after,
  });

  String get beforeLabel => _formatImpactValue(before);
  String get afterLabel => _formatImpactValue(after);
}

List<_PayloadImpact> _buildPayloadImpacts(
  Map<String, dynamic> previousPayload,
  Map<String, dynamic> currentPayload,
) {
  final previousBusiness = _extractBusinessPayload(previousPayload);
  final currentBusiness = _extractBusinessPayload(currentPayload);
  final impacts = <_PayloadImpact>[];
  _collectPayloadImpacts(previousBusiness, currentBusiness, '', impacts);
  impacts.sort((left, right) => left.path.compareTo(right.path));
  return impacts.take(80).toList(growable: false);
}

Map<String, dynamic> _extractBusinessPayload(Map<String, dynamic> payload) {
  final business = <String, dynamic>{};
  for (final key in const <String>[
    'campaign',
    'answers',
    'criterionAnswers',
    'assignments',
    'criterionAssignments',
  ]) {
    if (payload.containsKey(key)) {
      business[key] = payload[key];
    }
  }
  return business.isEmpty ? payload : business;
}

void _collectPayloadImpacts(
  Object? before,
  Object? after,
  String path,
  List<_PayloadImpact> impacts,
) {
  if (_sameJsonValue(before, after)) {
    return;
  }

  if (before is Map || after is Map) {
    final beforeMap = _jsonObject(before) ?? <String, dynamic>{};
    final afterMap = _jsonObject(after) ?? <String, dynamic>{};
    final keys = <String>{
      ...beforeMap.keys.map((key) => key.toString()),
      ...afterMap.keys.map((key) => key.toString()),
    }.where((key) => !_ignoredImpactKeys.contains(key)).toList()..sort();
    for (final key in keys) {
      final childPath = path.isEmpty ? key : '$path.$key';
      _collectPayloadImpacts(beforeMap[key], afterMap[key], childPath, impacts);
    }
    return;
  }

  if (before is List || after is List) {
    final beforeList = before is List ? before : const <Object?>[];
    final afterList = after is List ? after : const <Object?>[];
    final beforeById = _listByBusinessId(beforeList);
    final afterById = _listByBusinessId(afterList);
    if (beforeById != null || afterById != null) {
      final left = beforeById ?? const <String, Object?>{};
      final right = afterById ?? const <String, Object?>{};
      final keys = <String>{...left.keys, ...right.keys}.toList()..sort();
      for (final key in keys) {
        _collectPayloadImpacts(left[key], right[key], '$path[$key]', impacts);
      }
      return;
    }

    final maxLength = beforeList.length > afterList.length
        ? beforeList.length
        : afterList.length;
    for (var index = 0; index < maxLength; index += 1) {
      _collectPayloadImpacts(
        index < beforeList.length ? beforeList[index] : null,
        index < afterList.length ? afterList[index] : null,
        '$path[$index]',
        impacts,
      );
    }
    return;
  }

  final normalizedPath = path.isEmpty ? 'valeur' : path;
  impacts.add(
    _PayloadImpact(path: normalizedPath, before: before, after: after),
  );
}

Map<String, Object?>? _listByBusinessId(List<Object?> values) {
  if (values.isEmpty) {
    return const <String, Object?>{};
  }
  final result = <String, Object?>{};
  for (var index = 0; index < values.length; index += 1) {
    final item = values[index];
    final map = _jsonObject(item);
    if (map == null) {
      return null;
    }
    final id = _businessIdForMap(map);
    if (id == null || id.isEmpty) {
      return null;
    }
    result[id] = map;
  }
  return result;
}

String? _businessIdForMap(Map<String, dynamic> map) {
  for (final key in const <String>[
    'criterionId',
    'criterion_id',
    'id',
    'userId',
    'user_id',
    'campaignId',
    'campaign_id',
  ]) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

bool _sameJsonValue(Object? before, Object? after) {
  if (before == after) {
    return true;
  }
  try {
    return jsonEncode(before) == jsonEncode(after);
  } catch (_) {
    return before?.toString() == after?.toString();
  }
}

String _formatImpactValue(Object? value) {
  if (value == null) {
    return '—';
  }
  if (value is String) {
    return value.trim().isEmpty ? '""' : _truncateImpactValue(value);
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  try {
    return _truncateImpactValue(
      const JsonEncoder.withIndent('  ').convert(value),
    );
  } catch (_) {
    return _truncateImpactValue(value.toString());
  }
}

String _truncateImpactValue(String value) {
  const maxLength = 900;
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}…';
}

const _ignoredImpactKeys = <String>{
  'activityLog',
  'activity_log',
  'activity',
  'createdAt',
  'created_at',
  'updatedAt',
  'updated_at',
  'lastUpdatedAt',
  'last_updated_at',
  'syncedAt',
  'synced_at',
  'receivedAt',
  'received_at',
  'serverTime',
  'server_time',
  'serverSyncId',
  'server_sync_id',
  'payloadSha256',
  'payload_sha256',
};

List<Map<String, dynamic>> _jsonList(Object? value) {
  if (value is List) {
    return value
        .whereType<Object>()
        .map(_jsonObject)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
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

int _intFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
