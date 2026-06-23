import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/assessment_quality_service.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../assessment/assessment_import_screen.dart';
import '../assessment/assessment_screen.dart';

class CampaignListScreen extends StatefulWidget {
  final IrnReferential referential;

  const CampaignListScreen({
    required this.referential,
    super.key,
  });

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  final _campaignRepository = const LocalCampaignRepository();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _activityRepository = const LocalActivityRepository();
  final _scoringService = const OfficialRnrScoringService();
  final _qualityService = const AssessmentQualityService();

  late Future<List<_CampaignWithSummary>> _campaignsFuture;

  @override
  void initState() {
    super.initState();
    _campaignsFuture = _loadCampaigns();
  }

  Future<List<_CampaignWithSummary>> _loadCampaigns() async {
    final campaigns = await _campaignRepository.ensureDefaultCampaign(
      referentialId: widget.referential.id,
      referentialVersion: widget.referential.version,
    );

    final enriched = <_CampaignWithSummary>[];
    for (final campaign in campaigns) {
      final criterionAnswers = await _assessmentRepository.loadCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      final summary =
          _scoringService.computeSummary(widget.referential, answers);
      final qualityReport = _qualityService.buildReport(
        referential: widget.referential,
        criterionAnswers: criterionAnswers,
        campaign: campaign,
      );
      enriched.add(_CampaignWithSummary(
        campaign: campaign,
        criterionAnswers: criterionAnswers,
        answers: answers,
        summary: summary,
        qualityReport: qualityReport,
      ));
    }
    return enriched;
  }

  Future<void> _refresh() async {
    setState(() {
      _campaignsFuture = _loadCampaigns();
    });
    await _campaignsFuture;
  }

  Future<void> _importCampaign() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AssessmentImportScreen(referential: widget.referential),
      ),
    );
    if (imported == true) {
      await _refresh();
    }
  }

  Future<void> _createCampaign() async {
    final result = await showDialog<_CampaignFormResult>(
      context: context,
      builder: (_) => const _CampaignDetailsDialog(),
    );
    if (result == null || result.name.trim().isEmpty) {
      return;
    }

    final campaign = await _campaignRepository.createCampaign(
      referentialId: widget.referential.id,
      name: result.name,
      description: result.description,
      information: const CampaignInformation(),
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
    await _refresh();
  }

  Future<void> _deleteCampaign(LocalCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la campagne locale ?'),
        content: Text(
          'La campagne « ${campaign.name} » sera retirée de la liste. '
          'Les réponses locales associées seront aussi réinitialisées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonalIcon(
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

    await _activityRepository.appendEvent(
      LocalActivityEvent.create(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
        type: LocalActivityType.campaignDeleted,
        title: 'Campagne supprimée',
        description: campaign.name,
      ),
    );
    await _assessmentRepository.clearAnswers(
      referentialId: widget.referential.id,
      campaignId: campaign.id,
    );
    await _campaignRepository.deleteCampaign(
      referentialId: widget.referential.id,
      campaignId: campaign.id,
    );
    await _refresh();
  }

  Future<void> _changeStatus(
      _CampaignWithSummary entry, LocalCampaignStatus status) async {
    if (status == LocalCampaignStatus.readyForReview &&
        !entry.qualityReport.isReadyForReview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Les informations de campagne, les réponses et les justifications doivent être complètes avant revue.'),
        ),
      );
      return;
    }

    final updatedCampaign = await _campaignRepository.updateCampaignStatus(
      referentialId: widget.referential.id,
      campaignId: entry.campaign.id,
      status: status,
    );
    if (updatedCampaign != null && entry.campaign.status != status) {
      await _activityRepository.appendEvent(
        LocalActivityEvent.create(
          referentialId: widget.referential.id,
          campaignId: entry.campaign.id,
          type: LocalActivityType.campaignStatusChanged,
          title: 'Statut modifié',
          description: entry.campaign.name,
          fromValue: entry.campaign.status.label,
          toValue: status.label,
        ),
      );
    }
    await _refresh();
  }

  Future<void> _openCampaign(LocalCampaign campaign) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentScreen(
          referential: widget.referential,
          campaign: campaign,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campagnes locales'),
        actions: [
          TextButton.icon(
            onPressed: _importCampaign,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Importer JSON'),
          ),
          TextButton.icon(
            onPressed: _createCampaign,
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle campagne'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<_CampaignWithSummary>>(
        future: _campaignsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
                error: snapshot.error.toString(), onRetry: _refresh);
          }

          final campaigns = snapshot.data ?? <_CampaignWithSummary>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeaderCard(referential: widget.referential),
                  const SizedBox(height: 12),
                  for (final campaign in campaigns)
                    _CampaignCard(
                      entry: campaign,
                      onOpen: () => _openCampaign(campaign.campaign),
                      onDelete: campaigns.length <= 1
                          ? null
                          : () => _deleteCampaign(campaign.campaign),
                      onStatusChanged: (status) =>
                          _changeStatus(campaign, status),
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

class _CampaignWithSummary {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final Map<String, IrnAnswer> answers;
  final IrnScoreSummary summary;
  final AssessmentQualityReport qualityReport;

  const _CampaignWithSummary({
    required this.campaign,
    required this.criterionAnswers,
    required this.answers,
    required this.summary,
    required this.qualityReport,
  });
}

class _HeaderCard extends StatelessWidget {
  final IrnReferential referential;

  const _HeaderCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.folder_copy_outlined, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Campagnes locales OpenIRN',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                      'Référentiel : ${referential.id} · ${referential.version}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Une campagne locale regroupe une saisie R / NR, sa synthèse, son contrôle qualité, '
                    'son export JSON et maintenant un statut de workflow.',
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

class _CampaignCard extends StatelessWidget {
  final _CampaignWithSummary entry;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final ValueChanged<LocalCampaignStatus> onStatusChanged;

  const _CampaignCard({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final campaign = entry.campaign;
    final summary = entry.summary;
    final qualityReport = entry.qualityReport;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (campaign.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(campaign.description),
                      ],
                      if (campaign.information.systemName
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'SI : ${campaign.information.systemName}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (campaign
                              .information.projectDirectorFullName.isNotEmpty ||
                          campaign.information.projectDirectorEmail
                              .trim()
                              .isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Directeur projet : ${_projectDirectorLabel(campaign.information)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(summary.formattedOfficialScore,
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: summary.officialScore == null
                  ? 0
                  : summary.officialScore! / 100,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(campaign.status.label),
                ),
                Chip(
                    label: Text(
                        'Cotés : ${summary.answeredCriteria}/${summary.totalCriteria}')),
                Chip(label: Text('R : ${summary.resilientCriteria}')),
                Chip(label: Text('NR : ${summary.nonResilientCriteria}')),
                Chip(
                    label: Text(
                        'Complétude : ${(summary.completionRate * 100).toStringAsFixed(0)} %')),
                Chip(label: Text('Maj : ${_formatDate(campaign.updatedAt)}')),
                Chip(
                  avatar: Icon(
                    qualityReport.isCampaignInformationComplete
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                  ),
                  label: Text(
                    qualityReport.isCampaignInformationComplete
                        ? 'Infos campagne OK'
                        : 'Infos manquantes : ${qualityReport.missingCampaignInformationCount}',
                  ),
                ),
                if (campaign.isReadOnly)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 18),
                    label: Text('Lecture seule'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(campaign.status.helperText,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            _StatusActions(
              status: campaign.status,
              qualityReport: qualityReport,
              onStatusChanged: onStatusChanged,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onDelete != null) ...[
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Ouvrir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _projectDirectorLabel(CampaignInformation information) {
    final name = information.projectDirectorFullName;
    final email = information.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name <$email>';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return 'non renseigné';
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

class _StatusActions extends StatelessWidget {
  final LocalCampaignStatus status;
  final AssessmentQualityReport qualityReport;
  final ValueChanged<LocalCampaignStatus> onStatusChanged;

  const _StatusActions({
    required this.status,
    required this.qualityReport,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmitForReview = qualityReport.isReadyForReview;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (status == LocalCampaignStatus.draft)
          FilledButton.tonalIcon(
            onPressed: canSubmitForReview
                ? () => onStatusChanged(LocalCampaignStatus.readyForReview)
                : null,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Prêt pour revue'),
          ),
        if (status == LocalCampaignStatus.readyForReview) ...[
          TextButton.icon(
            onPressed: () => onStatusChanged(LocalCampaignStatus.draft),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Repasser en brouillon'),
          ),
          FilledButton.icon(
            onPressed: () => onStatusChanged(LocalCampaignStatus.validated),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Valider'),
          ),
        ],
        if (status == LocalCampaignStatus.validated) ...[
          TextButton.icon(
            onPressed: () => onStatusChanged(LocalCampaignStatus.draft),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Rouvrir'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => onStatusChanged(LocalCampaignStatus.archived),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archiver'),
          ),
        ],
        if (status == LocalCampaignStatus.archived)
          TextButton.icon(
            onPressed: () => onStatusChanged(LocalCampaignStatus.draft),
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('Rouvrir en brouillon'),
          ),
        if (status == LocalCampaignStatus.draft && !canSubmitForReview)
          const Chip(
            avatar: Icon(Icons.info_outline, size: 18),
            label: Text('Qualité incomplète'),
          ),
      ],
    );
  }
}

class _CampaignFormResult {
  final String name;
  final String description;

  const _CampaignFormResult({
    required this.name,
    required this.description,
  });
}

class _CampaignDetailsDialog extends StatefulWidget {
  const _CampaignDetailsDialog();

  @override
  State<_CampaignDetailsDialog> createState() => _CampaignDetailsDialogState();
}

class _CampaignDetailsDialogState extends State<_CampaignDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
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
      title: const Text('Nouvelle campagne locale'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom de la campagne',
                  hintText: 'Ex. Évaluation IRN 2026 — SI Facturation',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom de campagne est obligatoire.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description de la campagne',
                  hintText: 'Périmètre, contexte ou objectif de l’évaluation.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Les informations détaillées du système d’information et du directeur de projet se saisissent une fois la campagne ouverte.',
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
        FilledButton(
          onPressed: _submit,
          child: const Text('Créer'),
        ),
      ],
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
            Text('Impossible de charger les campagnes locales : $error'),
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
