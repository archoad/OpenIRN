import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/files/local_json_file_service.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/assessment_export_service.dart';

class AssessmentExportScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;

  const AssessmentExportScreen({
    required this.referential,
    required this.campaign,
    required this.criterionAnswers,
    super.key,
  });

  @override
  State<AssessmentExportScreen> createState() => _AssessmentExportScreenState();
}

class _AssessmentExportScreenState extends State<AssessmentExportScreen> {
  final LocalActivityRepository _activityRepository =
      const LocalActivityRepository();
  final LocalJsonFileService _fileService = const LocalJsonFileService();
  late final Future<List<LocalActivityEvent>> _activityEventsFuture;

  bool _isSaving = false;
  String? _fileErrorMessage;

  @override
  void initState() {
    super.initState();
    _activityEventsFuture = _activityRepository.loadEvents(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LocalActivityEvent>>(
      future: _activityEventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Export JSON')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final activityEvents = snapshot.data ?? const <LocalActivityEvent>[];
        const exportService = AssessmentExportService();
        final jsonPayload = exportService.buildPrettyJson(
          referential: widget.referential,
          campaign: widget.campaign,
          criterionAnswers: widget.criterionAnswers,
          activityEvents: activityEvents,
        );
        final answeredCount = widget.criterionAnswers.values
            .where((answer) => answer.answer.isCounted)
            .length;
        final justificationCount = widget.criterionAnswers.values
            .where((answer) => answer.justification.trim().isNotEmpty)
            .length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Export JSON'),
            actions: [
              TextButton.icon(
                onPressed: () => _copyToClipboard(context, jsonPayload),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copier'),
              ),
              TextButton.icon(
                onPressed:
                    _isSaving ? null : () => _saveToFile(context, jsonPayload),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_outlined),
                label: Text(_isSaving ? 'Enregistrement…' : 'Enregistrer'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ExportIntroCard(
                    referential: widget.referential,
                    campaign: widget.campaign,
                    answeredCount: answeredCount,
                    justificationCount: justificationCount,
                    activityEventCount: activityEvents.length,
                    onCopy: () => _copyToClipboard(context, jsonPayload),
                    onSave: _isSaving
                        ? null
                        : () => _saveToFile(context, jsonPayload),
                    isSaving: _isSaving,
                  ),
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 12),
                    const _ExportWarningCard(
                      message:
                          'Le journal d’activité n’a pas pu être chargé. L’export reste utilisable, mais il ne contient pas la trace locale.',
                    ),
                  ],
                  if (_fileErrorMessage != null) ...[
                    const SizedBox(height: 12),
                    _ExportWarningCard(message: _fileErrorMessage!),
                  ],
                  const SizedBox(height: 12),
                  _JsonPreviewCard(jsonPayload: jsonPayload),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveToFile(BuildContext context, String jsonPayload) async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
      _fileErrorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ouverture du dialogue d’enregistrement…')),
    );

    try {
      final path = await _fileService.saveJson(
        content: jsonPayload,
        suggestedName: _fileService.buildExportFileName(
          campaignName: widget.campaign.name,
          referentialVersion: widget.referential.version,
        ),
      );
      if (!context.mounted) {
        return;
      }
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export fichier annulé.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export JSON enregistré : $path')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      setState(() {
        _fileErrorMessage = 'Enregistrement impossible : $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard(
      BuildContext context, String jsonPayload) async {
    await Clipboard.setData(ClipboardData(text: jsonPayload));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Export JSON copié dans le presse-papiers.')),
    );
  }
}

class _ExportIntroCard extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final int answeredCount;
  final int justificationCount;
  final int activityEventCount;
  final VoidCallback onCopy;
  final VoidCallback? onSave;
  final bool isSaving;

  const _ExportIntroCard({
    required this.referential,
    required this.campaign,
    required this.answeredCount,
    required this.justificationCount,
    required this.activityEventCount,
    required this.onCopy,
    required this.onSave,
    required this.isSaving,
  });

  String _projectDirectorLabel(CampaignInformation info) {
    if (info.projectDirectorFullName.isNotEmpty) {
      return info.projectDirectorFullName;
    }
    if (info.projectDirectorEmail.trim().isNotEmpty) {
      return info.projectDirectorEmail.trim();
    }
    return 'non renseigné';
  }

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
              children: [
                const Icon(Icons.data_object_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Export local de l’évaluation',
                      style: theme.textTheme.titleLarge),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onSave,
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt_outlined),
                      label: Text(
                          isSaving ? 'Enregistrement…' : 'Enregistrer .json'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copier'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Cet export sert de contrat intermédiaire avant la future synchronisation API. '
              'Il contient la traçabilité du référentiel officiel, la campagne, les réponses R / NR / N.C., les justifications, les scores calculés et le journal d’activité local. '
              'Tu peux l’enregistrer en fichier .json ou le copier dans le presse-papiers.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Campagne : ${campaign.name}')),
                Chip(label: Text('Statut : ${campaign.status.label}')),
                Chip(
                    label: Text(
                        'SI : ${campaign.information.systemName.trim().isEmpty ? 'non renseigné' : campaign.information.systemName}')),
                Chip(
                    label: Text(
                        'Directeur : ${_projectDirectorLabel(campaign.information)}')),
                Chip(label: Text('Référentiel : ${referential.id}')),
                Chip(label: Text('Version : ${referential.version}')),
                Chip(label: Text('Réponses cotées : $answeredCount')),
                Chip(label: Text('Justifications : $justificationCount')),
                Chip(label: Text('Évènements journal : $activityEventCount')),
                Chip(
                    label: Text(
                        'Critères exportés : ${referential.criteria.length}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportWarningCard extends StatelessWidget {
  final String message;

  const _ExportWarningCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber_outlined,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _JsonPreviewCard extends StatelessWidget {
  final String jsonPayload;

  const _JsonPreviewCard({required this.jsonPayload});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.preview_outlined),
                const SizedBox(width: 8),
                Text('Aperçu JSON',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SelectableText(
                jsonPayload,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
