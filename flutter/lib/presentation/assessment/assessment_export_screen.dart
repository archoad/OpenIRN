import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/files/local_json_file_service.dart';
import '../../l10n/openirn_localizations.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_criterion_assignment_repository.dart';
import '../../data/repositories/local_user_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/criterion_assignment.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/assessment_export_service.dart';
import '../common/openirn_app_bar.dart';

class _ExportContext {
  final List<LocalActivityEvent> activityEvents;
  final List<AppUser> users;
  final List<CriterionAssignment> assignments;

  const _ExportContext({
    this.activityEvents = const <LocalActivityEvent>[],
    this.users = const <AppUser>[],
    this.assignments = const <CriterionAssignment>[],
  });
}

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
  final LocalUserRepository _userRepository = const LocalUserRepository();
  final LocalCriterionAssignmentRepository _assignmentRepository =
      const LocalCriterionAssignmentRepository();
  final LocalJsonFileService _fileService = const LocalJsonFileService();
  late final Future<_ExportContext> _exportContextFuture;

  bool _isSaving = false;
  String? _fileErrorMessage;

  @override
  void initState() {
    super.initState();
    _exportContextFuture = _loadExportContext();
  }

  Future<_ExportContext> _loadExportContext() async {
    final activityEvents = await _activityRepository.loadEvents(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
    final users = await _userRepository.ensureDefaultUsers();
    final assignments = await _assignmentRepository.loadAssignments(
      referentialId: widget.referential.id,
      campaignId: widget.campaign.id,
    );
    return _ExportContext(
      activityEvents: activityEvents,
      users: users,
      assignments: assignments,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ExportContext>(
      future: _exportContextFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            appBar: OpenIrnAppBar(title: 'Export JSON'),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final exportContext = snapshot.data ?? const _ExportContext();
        final activityEvents = exportContext.activityEvents;
        const exportService = AssessmentExportService();
        final jsonPayload = exportService.buildPrettyJson(
          referential: widget.referential,
          campaign: widget.campaign,
          criterionAnswers: widget.criterionAnswers,
          activityEvents: activityEvents,
          users: exportContext.users,
          assignments: exportContext.assignments,
        );
        final answeredCount = widget.criterionAnswers.values
            .where((answer) => answer.answer.isCounted)
            .length;
        final justificationCount = widget.criterionAnswers.values
            .where((answer) => answer.justification.trim().isNotEmpty)
            .length;

        return Scaffold(
          appBar: OpenIrnAppBar(
            title: 'Export JSON',
            actions: [
              OpenIrnAppBarAction(
                id: 'copy',
                label: context.tr('action.copy', fallback: 'Copier'),
                icon: Icons.copy_all_outlined,
                onSelected: () => _copyToClipboard(context, jsonPayload),
              ),
              OpenIrnAppBarAction(
                id: 'save',
                label: _isSaving
                    ? context.tr(
                        'export.action.saving',
                        fallback: 'Enregistrement…',
                      )
                    : context.tr('action.save', fallback: 'Enregistrer'),
                icon: Icons.save_alt_outlined,
                enabled: !_isSaving,
                onSelected: () => _saveToFile(context, jsonPayload),
              ),
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
                    assignmentCount: exportContext.assignments.length,
                    onCopy: () => _copyToClipboard(context, jsonPayload),
                    onSave: _isSaving
                        ? null
                        : () => _saveToFile(context, jsonPayload),
                    isSaving: _isSaving,
                  ),
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 12),
                    _ExportWarningCard(
                      message: context.tr(
                        'export.warning.activity_unavailable',
                        fallback:
                            'Le journal d’activité n’a pas pu être chargé. L’export reste utilisable, mais il ne contient pas la trace locale.',
                      ),
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
      SnackBar(
        content: Text(
          context.tr(
            'export.snackbar.open_save_dialog',
            fallback: 'Ouverture du dialogue d’enregistrement…',
          ),
        ),
      ),
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
          SnackBar(
            content: Text(
              context.tr(
                'export.snackbar.cancelled',
                fallback: 'Export fichier annulé.',
              ),
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'export.snackbar.saved',
              fallback: 'Export JSON enregistré : {path}',
              values: {'path': path},
            ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      setState(() {
        _fileErrorMessage = context.tr(
          'export.error.save_failed',
          fallback: 'Enregistrement impossible : {error}',
          values: {'error': error},
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_fileErrorMessage!)));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard(
    BuildContext context,
    String jsonPayload,
  ) async {
    await Clipboard.setData(ClipboardData(text: jsonPayload));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'export.snackbar.copied',
            fallback: 'Export JSON copié dans le presse-papiers.',
          ),
        ),
      ),
    );
  }
}

class _ExportIntroCard extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final int answeredCount;
  final int justificationCount;
  final int activityEventCount;
  final int assignmentCount;
  final VoidCallback onCopy;
  final VoidCallback? onSave;
  final bool isSaving;

  const _ExportIntroCard({
    required this.referential,
    required this.campaign,
    required this.answeredCount,
    required this.justificationCount,
    required this.activityEventCount,
    required this.assignmentCount,
    required this.onCopy,
    required this.onSave,
    required this.isSaving,
  });

  String _projectDirectorLabel(BuildContext context, CampaignInformation info) {
    if (info.projectDirectorFullName.isNotEmpty) {
      return info.projectDirectorFullName;
    }
    if (info.projectDirectorEmail.trim().isNotEmpty) {
      return info.projectDirectorEmail.trim();
    }
    return context.tr('common.not_provided', fallback: 'non renseigné');
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
                  child: Text(
                    context.tr(
                      'export.intro.title',
                      fallback: 'Export local de l’évaluation',
                    ),
                    style: theme.textTheme.titleLarge,
                  ),
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
                        isSaving
                            ? context.tr(
                                'export.action.saving',
                                fallback: 'Enregistrement…',
                              )
                            : context.tr(
                                'export.action.save_json',
                                fallback: 'Enregistrer .json',
                              ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(
                        context.tr('action.copy', fallback: 'Copier'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'export.intro.description',
                fallback:
                    'Cet export sert de format d’échange avant la future synchronisation serveur. Il contient la traçabilité du référentiel officiel, la campagne, les notes IRN, les justifications, les scores calculés et le journal d’activité local. Vous pouvez l’enregistrer au format JSON ou le copier dans le presse-papiers.',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.campaign',
                      fallback: 'Campagne : {name}',
                      values: {'name': campaign.name},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.status',
                      fallback: 'Statut : {status}',
                      values: {'status': context.trText(campaign.status.label)},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.system',
                      fallback: 'SI : {system}',
                      values: {
                        'system': campaign.information.systemName.trim().isEmpty
                            ? context.tr(
                                'common.not_provided',
                                fallback: 'non renseigné',
                              )
                            : campaign.information.systemName,
                      },
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.director',
                      fallback: 'Directeur : {director}',
                      values: {
                        'director': _projectDirectorLabel(
                          context,
                          campaign.information,
                        ),
                      },
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.referential',
                      fallback: 'Référentiel : {id}',
                      values: {'id': referential.id},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.version',
                      fallback: 'Version : {version}',
                      values: {'version': referential.version},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.rated_answers',
                      fallback: 'Réponses cotées : {count}',
                      values: {'count': answeredCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.justifications',
                      fallback: 'Justifications : {count}',
                      values: {'count': justificationCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.activity_events',
                      fallback: 'Évènements journal : {count}',
                      values: {'count': activityEventCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.assignments',
                      fallback: 'Affectations : {count}',
                      values: {'count': assignmentCount},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'export.chip.criteria',
                      fallback: 'Critères exportés : {count}',
                      values: {'count': referential.criteria.length},
                    ),
                  ),
                ),
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
            Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
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
                Text(
                  context.tr('export.preview.title', fallback: 'Aperçu JSON'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
