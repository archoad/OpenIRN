import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../l10n/openirn_localizations.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/services/access_policy_service.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_dialog.dart';
import '../../domain/models/local_campaign.dart';

class ActivityLogScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final AppUser activeUser;

  const ActivityLogScreen({
    required this.referential,
    required this.campaign,
    required this.activeUser,
    super.key,
  });

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _repository = const LocalActivityRepository();
  final _accessPolicy = const AccessPolicyService();
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
    if (!_accessPolicy.canClearCampaignActivityLog(widget.activeUser)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'activity.clear_forbidden',
              fallback: 'Votre profil ne permet pas d’effacer ce journal.',
            ),
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        insetPadding: responsiveDialogInsetPadding(context),
        title: Text(
          context.tr(
            'activity.clear_dialog.title',
            fallback: 'Effacer le journal ?',
          ),
        ),
        content: ResponsiveDialogContent(
          maxWidth: 560,
          child: Text(
            context.tr(
              'activity.clear_dialog.message',
              fallback:
                  'Le journal de la campagne “{campaign}” sera supprimé de ce terminal.',
              values: {'campaign': widget.campaign.name},
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('action.cancel', fallback: 'Annuler')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: Text(context.tr('action.clear', fallback: 'Effacer')),
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

    final clearedAt = DateTime.now();
    await _repository.saveEvents(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
      events: [
        LocalActivityEvent.create(
          referentialId: widget.referential.id,
          campaignId: widget.campaign.id,
          type: LocalActivityType.activityLogCleared,
          title: LocalActivityType.activityLogCleared.jsonValue,
          actorName: widget.activeUser.fullName.trim().isEmpty
              ? widget.activeUser.email
              : widget.activeUser.fullName,
          actorRole: widget.activeUser.role.jsonValue,
          now: clearedAt,
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('activity.clear_success', fallback: 'Journal effacé.'),
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: context.tr(
          'screen.activity.title',
          fallback: 'Journal d’activité',
        ),
        actions: [
          OpenIrnAppBarAction(
            id: 'refresh',
            label: context.tr('action.refresh', fallback: 'Actualiser'),
            icon: Icons.refresh,
            onSelected: _refresh,
          ),
          if (_accessPolicy.canClearCampaignActivityLog(widget.activeUser)) ...[
            const OpenIrnAppBarAction.divider(),
            OpenIrnAppBarAction(
              id: 'clear',
              label: context.tr(
                'activity.action.clear_log',
                fallback: 'Effacer le journal',
              ),
              icon: Icons.delete_outline,
              destructive: true,
              onSelected: _clearJournal,
            ),
          ],
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
                    context.tr(
                      'activity.header.referential_status',
                      fallback: 'Référentiel {version} · {status}',
                      values: {
                        'version': referential.version,
                        'status': context.trText(campaign.status.label),
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'activity.header.event_count',
                      fallback:
                          '{count} évènement(s) enregistré(s) localement pour cette campagne.',
                      values: {'count': eventCount},
                    ),
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
    final title = _localizedTitle(context);
    final description = _localizedDescription(context);

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
                      Text(title, style: theme.textTheme.titleMedium),
                      Chip(label: Text(context.trText(event.type.label))),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description),
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

  String _localizedTitle(BuildContext context) {
    if (event.type != LocalActivityType.activityLogCleared) {
      return event.title;
    }
    return context.tr(
      'activity.event.log_cleared.title',
      fallback: 'Journal d’activité effacé',
    );
  }

  String _localizedDescription(BuildContext context) {
    if (event.type != LocalActivityType.activityLogCleared) {
      return event.description;
    }
    final actorName = event.actorName?.trim() ?? '';
    final actorRole = event.actorRole?.trim() ?? '';
    if (actorName.isEmpty || actorRole.isEmpty) {
      return event.description;
    }
    return context.tr(
      'activity.event.log_cleared.description',
      fallback: 'Effacé par {name} ({role}).',
      values: {
        'name': actorName,
        'role': context.tr('role.$actorRole', fallback: actorRole),
      },
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
      case LocalActivityType.activityLogCleared:
        return Icons.delete_sweep_outlined;
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.history_toggle_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'activity.empty',
                fallback: 'Aucun évènement enregistré pour cette campagne.',
              ),
            ),
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
            Text(
              context.tr(
                'activity.error.load',
                fallback:
                    'Impossible de charger le journal d’activité : {error}',
                values: {'error': error},
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('action.retry', fallback: 'Réessayer')),
            ),
          ],
        ),
      ),
    );
  }
}
