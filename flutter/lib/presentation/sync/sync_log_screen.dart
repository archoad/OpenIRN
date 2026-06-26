import 'package:flutter/material.dart';

import '../../data/repositories/local_sync_log_repository.dart';
import '../../domain/models/sync_log_event.dart';
import '../common/openirn_app_bar.dart';

class SyncLogScreen extends StatefulWidget {
  const SyncLogScreen({super.key});

  @override
  State<SyncLogScreen> createState() => _SyncLogScreenState();
}

class _SyncLogScreenState extends State<SyncLogScreen> {
  final _repository = const LocalSyncLogRepository();
  late Future<List<SyncLogEvent>> _future;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _future = _repository.loadEvents();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repository.loadEvents();
    });
    await _future;
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vider le journal de synchronisation ?'),
        content: const Text(
          'Cette action supprime uniquement le journal de ce terminal de synchronisation. '
          'Elle ne supprime ni les campagnes, ni les exports, ni les snapshots serveur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Vider'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _clearing = true;
    });
    await _repository.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _clearing = false;
      _future = _repository.loadEvents();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Journal de synchronisation vidé.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Journal de synchronisation',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Actualiser',
            icon: Icons.refresh,
            onSelected: _refresh,
          ),
          OpenIrnAppBarAction(
            id: 'clear',
            label: 'Vider le journal',
            icon: Icons.delete_sweep_outlined,
            enabled: !_clearing,
            destructive: true,
            onSelected: _clear,
          ),
        ],
      ),
      body: FutureBuilder<List<SyncLogEvent>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossible de charger le journal : ${snapshot.error}',
                ),
              ),
            );
          }
          final events = snapshot.data ?? const <SyncLogEvent>[];
          if (events.isEmpty) {
            return const _EmptySyncLog();
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: events.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _SyncLogSummaryCard(events: events);
                  }
                  return _SyncLogEventCard(event: events[index - 1]);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptySyncLog extends StatelessWidget {
  const _EmptySyncLog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_alt_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucun évènement de synchronisation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Les tests de connexion, push, pull et imports de snapshots apparaîtront ici.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncLogSummaryCard extends StatelessWidget {
  final List<SyncLogEvent> events;

  const _SyncLogSummaryCard({required this.events});

  @override
  Widget build(BuildContext context) {
    final successCount = events.where((event) => event.type.isSuccess).length;
    final failureCount = events.length - successCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: const Icon(Icons.history, size: 18),
              label: Text('${events.length} évènement(s)'),
            ),
            Chip(
              avatar: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('$successCount succès'),
            ),
            Chip(
              avatar: const Icon(Icons.error_outline, size: 18),
              label: Text('$failureCount alerte(s)'),
            ),
            const Chip(label: Text('Rétention locale : 300 évènements')),
          ],
        ),
      ),
    );
  }
}

class _SyncLogEventCard extends StatelessWidget {
  final SyncLogEvent event;

  const _SyncLogEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final success = event.type.isSuccess;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: success
              ? colorScheme.primaryContainer
              : colorScheme.errorContainer,
          foregroundColor: success
              ? colorScheme.onPrimaryContainer
              : colorScheme.onErrorContainer,
          child: Icon(_iconFor(event.type)),
        ),
        title: Text(event.title.isEmpty ? event.type.label : event.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.message.isNotEmpty) Text(event.message),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(event.type.label)),
                  Chip(
                    label: Text(
                      'Tenant : ${event.tenantId.isEmpty ? '—' : event.tenantId}',
                    ),
                  ),
                  Chip(
                    label: Text(
                      'Appareil : ${event.deviceId.isEmpty ? '—' : event.deviceId}',
                    ),
                  ),
                  if (event.statusCode != null)
                    Chip(label: Text('HTTP ${event.statusCode}')),
                  if (event.serverSyncId != null)
                    Chip(label: Text('serverSyncId : ${event.serverSyncId}')),
                  if (event.sourceDeviceId != null)
                    Chip(label: Text('Source : ${event.sourceDeviceId}')),
                  if (event.campaignCount != null)
                    Chip(label: Text('${event.campaignCount} campagne(s)')),
                  if (event.snapshotCount != null)
                    Chip(label: Text('${event.snapshotCount} snapshot(s)')),
                ],
              ),
            ],
          ),
        ),
        trailing: Text(_formatDate(event.createdAt)),
        isThreeLine: true,
      ),
    );
  }

  IconData _iconFor(SyncLogEventType type) {
    switch (type) {
      case SyncLogEventType.connectionTest:
        return Icons.cloud_done_outlined;
      case SyncLogEventType.pushSucceeded:
        return Icons.cloud_upload_outlined;
      case SyncLogEventType.pushFailed:
        return Icons.cloud_off_outlined;
      case SyncLogEventType.pullSucceeded:
        return Icons.cloud_download_outlined;
      case SyncLogEventType.pullFailed:
        return Icons.error_outline;
      case SyncLogEventType.importSucceeded:
        return Icons.download_done_outlined;
      case SyncLogEventType.importFailed:
        return Icons.warning_amber_outlined;
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date\n$time';
  }
}
