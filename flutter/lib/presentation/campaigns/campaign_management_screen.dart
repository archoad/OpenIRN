import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/sync_automation_service.dart';
import '../common/openirn_app_bar.dart';
import '../common/responsive_autofocus.dart';
import '../common/responsive_dialog.dart';

class CampaignManagementScreen extends StatefulWidget {
  final IrnReferential referential;
  final AppUser activeUser;

  const CampaignManagementScreen({
    required this.referential,
    required this.activeUser,
    super.key,
  });

  @override
  State<CampaignManagementScreen> createState() =>
      _CampaignManagementScreenState();
}

class _CampaignManagementScreenState extends State<CampaignManagementScreen> {
  final _campaignRepository = const LocalCampaignRepository();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _assignmentRepository = const LocalCriterionAssignmentRepository();
  final _activityRepository = const LocalActivityRepository();
  final _syncAutomationService = const SyncAutomationService();
  final _appSyncCoordinator = AppSyncCoordinator.instance;

  late Future<List<LocalCampaign>> _campaignsFuture;
  int _lastAppliedSyncSerial = 0;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _campaignsFuture = _loadCampaigns();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
  }

  @override
  void dispose() {
    _appSyncCoordinator.removeListener(_handleBackgroundSyncUpdate);
    super.dispose();
  }

  void _handleBackgroundSyncUpdate() {
    final serial = _appSyncCoordinator.changeSerial;
    if (!mounted || serial == _lastAppliedSyncSerial) {
      return;
    }
    _lastAppliedSyncSerial = serial;
    _refresh();
  }

  Future<List<LocalCampaign>> _loadCampaigns() {
    return _campaignRepository.loadCampaigns(
      referentialId: widget.referential.id,
    );
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _campaignsFuture = _loadCampaigns();
    });
    await _campaignsFuture;
  }

  Future<void> _createCampaign() async {
    final result = await showDialog<_CampaignFormResult>(
      context: context,
      builder: (_) => const _CreateCampaignDialog(),
    );
    if (result == null) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      final campaign = await _campaignRepository.createCampaign(
        referentialId: widget.referential.id,
        name: result.name,
        description: result.description,
      );
      await _activityRepository.appendEvent(
        LocalActivityEvent.create(
          referentialId: widget.referential.id,
          campaignId: campaign.id,
          type: LocalActivityType.campaignCreated,
          title: 'Campagne créée',
          description: campaign.name,
        ),
      );
      final syncResult = await _syncAutomationService.pushLocalSnapshot(
        referential: widget.referential,
        activeUser: widget.activeUser,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${syncResult.title} — ${syncResult.message}'),
          ),
        );
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Future<void> _deleteCampaign(LocalCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteCampaignDialog(campaign: campaign),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      await _assessmentRepository.clearAnswers(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      await _assignmentRepository.saveAssignments(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
        assignments: const <CriterionAssignment>[],
      );
      await _activityRepository.clearEvents(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      await _campaignRepository.deleteCampaign(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );

      final syncResult = await _syncAutomationService.pushLocalSnapshot(
        referential: widget.referential,
        activeUser: widget.activeUser,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${syncResult.title} — ${syncResult.message}'),
          ),
        );
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Gérer les campagnes'),
      body: FutureBuilder<List<LocalCampaign>>(
        future: _campaignsFuture,
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

          final campaigns = snapshot.data ?? const <LocalCampaign>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeaderCard(
                    activeUser: widget.activeUser,
                    campaignCount: campaigns.length,
                    isWorking: _isWorking,
                    onCreate: _isWorking ? null : _createCampaign,
                  ),
                  const SizedBox(height: 12),
                  if (campaigns.isEmpty)
                    const _EmptyState()
                  else
                    for (final campaign in campaigns)
                      _ManagedCampaignCard(
                        campaign: campaign,
                        onDelete: _isWorking
                            ? null
                            : () => _deleteCampaign(campaign),
                      ),
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
  final AppUser activeUser;
  final int campaignCount;
  final bool isWorking;
  final VoidCallback? onCreate;

  const _HeaderCard({
    required this.activeUser,
    required this.campaignCount,
    required this.isWorking,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Administration des campagnes',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activeUser.displayName} · ${activeUser.role.label}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Créer une nouvelle campagne ou supprimer une campagne existante. '
                        'La suppression efface aussi les réponses, les affectations et le journal de la campagne concernée.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text('$campaignCount campagne(s)')),
                if (isWorking)
                  const Chip(
                    avatar: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: Text('Synchronisation en cours'),
                  ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Créer une campagne'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagedCampaignCard extends StatelessWidget {
  final LocalCampaign campaign;
  final VoidCallback? onDelete;

  const _ManagedCampaignCard({required this.campaign, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.name, style: theme.textTheme.titleMedium),
                      if (campaign.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(campaign.description),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(campaign.status.label)),
                Chip(label: Text('Maj : ${_formatDate(campaign.updatedAt)}')),
                Chip(label: Text('Créée : ${_formatDate(campaign.createdAt)}')),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class _CreateCampaignDialog extends StatefulWidget {
  const _CreateCampaignDialog();

  @override
  State<_CreateCampaignDialog> createState() => _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends State<_CreateCampaignDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _CampaignFormResult(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Créer une campagne'),
      content: ResponsiveDialogContent(
        maxWidth: 720,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: shouldAutofocusTextField(context),
                decoration: const InputDecoration(
                  labelText: 'Nom de la campagne',
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Le nom de la campagne est obligatoire.';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add),
          label: const Text('Créer'),
        ),
      ],
    );
  }
}

class _DeleteCampaignDialog extends StatelessWidget {
  final LocalCampaign campaign;

  const _DeleteCampaignDialog({required this.campaign});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: responsiveDialogInsetPadding(context),
      title: const Text('Supprimer la campagne ?'),
      content: ResponsiveDialogContent(
        maxWidth: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(campaign.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            const Text(
              'Cette action supprime la campagne de ce terminal, ses réponses, ses affectations et son journal. '
              'La suppression sera ensuite publiée au serveur pour synchroniser les autres terminaux.',
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
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Supprimer'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
        ),
      ],
    );
  }
}

class _CampaignFormResult {
  final String name;
  final String description;

  const _CampaignFormResult({required this.name, required this.description});
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
            Icon(Icons.folder_off_outlined, size: 44),
            SizedBox(height: 12),
            Text('Aucune campagne.'),
            SizedBox(height: 6),
            Text('Créez une première campagne depuis le bouton ci-dessus.'),
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
            Text('Impossible de charger la gestion des campagnes : $error'),
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
