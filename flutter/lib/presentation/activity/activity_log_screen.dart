import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_dialog.dart';
import '../../domain/models/local_campaign.dart';

class ActivityLogScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;

  const ActivityLogScreen({
    required this.referential,
    required this.campaign,
    super.key,
  });

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _repository = const LocalActivityRepository();
  late Future<List<LocalActivityEvent>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEvents();
  }

  Future<List<LocalActivityEvent>> _loadEvents() {
    return _repository.loadEvents(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _eventsFuture = _loadEvents();
    });
    await _eventsFuture;
  }

  Future<void> _clearJournal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: const Text('Effacer le journal ?'),
        content: ResponsiveDialogContent(
          maxWidth: 560,
          child: Text(
            'Le journal de la campagne “${widget.campaign.name}” sera supprimé de ce terminal.',
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
            label: const Text('Effacer'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _repository.clearEvents(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Journal effacé.')));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Journal d’activité',
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: 'Actualiser',
            icon: Icons.refresh,
            onSelected: _refresh,
          ),
          const OpenIrnAppBarAction.divider(),
          OpenIrnAppBarAction(
            id: 'clear',
            label: 'Effacer le journal',
            icon: Icons.delete_outline,
            destructive: true,
            onSelected: _clearJournal,
          ),
        ],
      ),
      body: FutureBuilder<List<LocalActivityEvent>>(
        future: _eventsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final events = snapshot.data ?? <LocalActivityEvent>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeaderCard(
                    referential: widget.referential,
                    campaign: widget.campaign,
                    eventCount: events.length,
                  ),
                  const SizedBox(height: 12),
                  if (events.isEmpty)
                    const _EmptyState()
                  else
                    for (final event in events)
                      _ActivityEventCard(event: event),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final int eventCount;

  const _HeaderCard({
    required this.referential,
    required this.campaign,
    required this.eventCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.history_outlined, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(campaign.name, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Référentiel ${referential.version} · ${campaign.status.label}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$eventCount évènement(s) enregistré(s) localement pour cette campagne.',
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

class _ActivityEventCard extends StatelessWidget {
  final LocalActivityEvent event;

  const _ActivityEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconForType(event.type)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(event.title, style: theme.textTheme.titleMedium),
                      Chip(label: Text(event.type.label)),
                    ],
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(event.description),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(_formatDate(event.createdAt))),
                      if (event.criterionId != null)
                        Chip(label: Text(event.criterionId!)),
                      if (event.fromValue != null || event.toValue != null)
                        Chip(
                          label: Text(
                            '${event.fromValue ?? '—'} → ${event.toValue ?? '—'}',
                          ),
                        ),
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

  IconData _iconForType(LocalActivityType type) {
    switch (type) {
      case LocalActivityType.campaignCreated:
        return Icons.add_circle_outline;
      case LocalActivityType.campaignDeleted:
        return Icons.delete_outline;
      case LocalActivityType.campaignStatusChanged:
        return Icons.flag_outlined;
      case LocalActivityType.campaignInformationUpdated:
        return Icons.info_outline;
      case LocalActivityType.assignmentChanged:
        return Icons.assignment_ind_outlined;
      case LocalActivityType.answerChanged:
        return Icons.check_circle_outline;
      case LocalActivityType.justificationChanged:
        return Icons.notes_outlined;
      case LocalActivityType.answersReset:
        return Icons.restart_alt_outlined;
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.history_toggle_off_outlined, size: 44),
            SizedBox(height: 12),
            Text('Aucun évènement enregistré pour cette campagne.'),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text('Impossible de charger le journal d’activité : $error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
