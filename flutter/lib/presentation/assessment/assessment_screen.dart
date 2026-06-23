import 'package:flutter/material.dart';

import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/local_activity_event.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../activity/activity_log_screen.dart';
import 'assessment_export_screen.dart';
import 'assessment_quality_screen.dart';
import 'assessment_summary_screen.dart';

class AssessmentScreen extends StatefulWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;

  const AssessmentScreen({
    required this.referential,
    required this.campaign,
    super.key,
  });

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final _catalogService = const ReferentialCatalogService();
  final _scoringService = const OfficialRnrScoringService();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _campaignRepository = const LocalCampaignRepository();
  final _activityRepository = const LocalActivityRepository();
  final Map<String, CriterionAnswer> _criterionAnswers =
      <String, CriterionAnswer>{};

  late LocalCampaign _campaign;

  bool _isLoadingAnswers = true;
  bool _isSavingAnswers = false;
  String? _localStatusMessage;

  Map<String, IrnAnswer> get _answers => <String, IrnAnswer>{
        for (final entry in _criterionAnswers.entries)
          entry.key: entry.value.answer,
      };

  int get _justificationCount {
    return _criterionAnswers.values
        .where((answer) => answer.justification.trim().isNotEmpty)
        .length;
  }

  @override
  void initState() {
    super.initState();
    _campaign = widget.campaign;
    _loadLocalAnswers();
  }

  Future<void> _loadLocalAnswers() async {
    try {
      final criterionAnswers = await _assessmentRepository.loadCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _criterionAnswers
          ..clear()
          ..addAll(criterionAnswers);
        _isLoadingAnswers = false;
        _localStatusMessage = criterionAnswers.isEmpty
            ? 'Aucune évaluation locale enregistrée.'
            : 'Évaluation locale restaurée (${criterionAnswers.length} critère(s), $_justificationCount justification(s)).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAnswers = false;
        _localStatusMessage =
            'Impossible de restaurer l’évaluation locale : $error';
      });
    }
  }

  Future<void> _setAnswer(IrnCriterion criterion, IrnAnswer answer) async {
    if (_campaign.isReadOnly) {
      return;
    }
    final previousAnswers = Map<String, CriterionAnswer>.of(_criterionAnswers);
    final current = _criterionAnswers[criterion.id] ??
        CriterionAnswer(
          criterionId: criterion.id,
          answer: IrnAnswer.notAnswered,
        );
    final previousAnswer = current.answer;
    final updated = current.copyWith(
      answer: answer,
      justification:
          answer == IrnAnswer.notAnswered ? '' : current.justification,
    );

    setState(() {
      _upsertCriterionAnswer(updated);
      _isSavingAnswers = true;
      _localStatusMessage = 'Sauvegarde locale en cours…';
    });

    final saved = await _saveOrRollback(previousAnswers);
    if (saved && previousAnswer != answer) {
      await _recordActivity(
        type: LocalActivityType.answerChanged,
        title: 'Réponse modifiée',
        description: '${criterion.code} — ${criterion.label}',
        criterionId: criterion.id,
        fromValue: previousAnswer.label,
        toValue: answer.label,
      );
    }
  }

  Future<void> _setJustification(
      IrnCriterion criterion, String justification) async {
    if (_campaign.isReadOnly) {
      return;
    }
    final previousAnswers = Map<String, CriterionAnswer>.of(_criterionAnswers);
    final current = _criterionAnswers[criterion.id] ??
        CriterionAnswer(
          criterionId: criterion.id,
          answer: IrnAnswer.notAnswered,
        );
    final previousJustification = current.justification.trim();
    final updatedJustification = justification.trim();
    final updated = current.copyWith(justification: updatedJustification);

    setState(() {
      _upsertCriterionAnswer(updated);
      _isSavingAnswers = true;
      _localStatusMessage = 'Sauvegarde de la justification en cours…';
    });

    final saved = await _saveOrRollback(previousAnswers);
    if (saved && previousJustification != updatedJustification) {
      await _recordActivity(
        type: LocalActivityType.justificationChanged,
        title: updatedJustification.isEmpty
            ? 'Justification supprimée'
            : 'Justification modifiée',
        description: '${criterion.code} — ${criterion.label}',
        criterionId: criterion.id,
        fromValue: previousJustification.isEmpty ? 'vide' : 'renseignée',
        toValue: updatedJustification.isEmpty ? 'vide' : 'renseignée',
      );
    }
  }

  void _upsertCriterionAnswer(CriterionAnswer answer) {
    final hasUsefulContent = answer.answer != IrnAnswer.notAnswered ||
        answer.justification.trim().isNotEmpty;
    if (!hasUsefulContent) {
      _criterionAnswers.remove(answer.criterionId);
      return;
    }
    _criterionAnswers[answer.criterionId] = answer;
  }

  Future<bool> _saveOrRollback(
      Map<String, CriterionAnswer> previousAnswers) async {
    try {
      await _assessmentRepository.saveCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
        answers: _criterionAnswers,
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _isSavingAnswers = false;
        _localStatusMessage =
            'Évaluation sauvegardée localement ($_justificationCount justification(s)).';
      });
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _criterionAnswers
          ..clear()
          ..addAll(previousAnswers);
        _isSavingAnswers = false;
        _localStatusMessage = 'Erreur de sauvegarde locale : $error';
      });
      return false;
    }
  }

  Future<bool> _confirmResetAnswers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Réinitialiser la campagne ?'),
        content: const Text(
          'Cette action supprimera toutes les réponses R / NR et toutes les justifications de cette campagne. '
          'Elle ne peut pas être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _resetAnswers() async {
    if (_campaign.isReadOnly || _criterionAnswers.isEmpty) {
      return;
    }

    final confirmed = await _confirmResetAnswers();
    if (!confirmed || !mounted) {
      return;
    }

    final previousAnswers = Map<String, CriterionAnswer>.of(_criterionAnswers);

    setState(() {
      _criterionAnswers.clear();
      _isSavingAnswers = true;
      _localStatusMessage = 'Réinitialisation locale en cours…';
    });

    try {
      await _assessmentRepository.clearAnswers(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingAnswers = false;
        _localStatusMessage = 'Évaluation locale réinitialisée.';
      });
      await _recordActivity(
        type: LocalActivityType.answersReset,
        title: 'Réponses réinitialisées',
        description:
            'Toutes les réponses et justifications locales de la campagne ont été supprimées.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _criterionAnswers
          ..clear()
          ..addAll(previousAnswers);
        _isSavingAnswers = false;
        _localStatusMessage = 'Erreur de réinitialisation locale : $error';
      });
    }
  }

  Future<void> _recordActivity({
    required LocalActivityType type,
    required String title,
    String description = '',
    String? criterionId,
    String? fromValue,
    String? toValue,
  }) async {
    await _activityRepository.appendEvent(
      LocalActivityEvent.create(
        referentialId: widget.referential.id,
        campaignId: _campaign.id,
        type: type,
        title: title,
        description: description,
        criterionId: criterionId,
        fromValue: fromValue,
        toValue: toValue,
      ),
    );
  }

  Future<void> _editCampaignInformation() async {
    if (_campaign.isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La campagne est en lecture seule.')),
      );
      return;
    }

    final result = await showDialog<_CampaignInformationFormResult>(
      context: context,
      builder: (_) => _CampaignInformationDialog(campaign: _campaign),
    );
    if (result == null) {
      return;
    }

    final updatedCampaign = await _campaignRepository.updateCampaignInformation(
      referentialId: widget.referential.id,
      campaignId: _campaign.id,
      name: result.name,
      description: result.description,
      information: result.information,
    );
    if (updatedCampaign == null) {
      return;
    }

    setState(() {
      _campaign = updatedCampaign;
      _localStatusMessage = 'Informations de campagne sauvegardées localement.';
    });

    await _recordActivity(
      type: LocalActivityType.campaignInformationUpdated,
      title: 'Informations campagne modifiées',
      description: updatedCampaign.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final answers = _answers;
    final canEdit = !_campaign.isReadOnly;
    final summary = _scoringService.computeSummary(widget.referential, answers);
    final criteriaByPillar =
        _catalogService.criteriaByPillar(widget.referential);

    return Scaffold(
      appBar: AppBar(
        title: Text(_campaign.name),
        actions: [
          TextButton.icon(
            onPressed:
                _isLoadingAnswers || !canEdit ? null : _editCampaignInformation,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Informations'),
          ),
          TextButton.icon(
            onPressed: _isLoadingAnswers
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AssessmentSummaryScreen(
                          referential: widget.referential,
                          campaign: _campaign,
                          criterionAnswers:
                              Map<String, CriterionAnswer>.unmodifiable(
                                  _criterionAnswers),
                        ),
                      ),
                    ),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('Synthèse'),
          ),
          TextButton.icon(
            onPressed: _isLoadingAnswers
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AssessmentExportScreen(
                          referential: widget.referential,
                          campaign: _campaign,
                          criterionAnswers:
                              Map<String, CriterionAnswer>.unmodifiable(
                                  _criterionAnswers),
                        ),
                      ),
                    ),
            icon: const Icon(Icons.data_object_outlined),
            label: const Text('Export JSON'),
          ),
          TextButton.icon(
            onPressed: _isLoadingAnswers
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AssessmentQualityScreen(
                          referential: widget.referential,
                          campaign: _campaign,
                          criterionAnswers:
                              Map<String, CriterionAnswer>.unmodifiable(
                                  _criterionAnswers),
                        ),
                      ),
                    ),
            icon: const Icon(Icons.rule_folder_outlined),
            label: const Text('Qualité'),
          ),
          TextButton.icon(
            onPressed: _isLoadingAnswers
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityLogScreen(
                          referential: widget.referential,
                          campaign: _campaign,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.history_outlined),
            label: const Text('Journal'),
          ),
          TextButton.icon(
            onPressed: !canEdit ||
                    _criterionAnswers.isEmpty ||
                    _isLoadingAnswers ||
                    _isSavingAnswers
                ? null
                : _resetAnswers,
            icon: const Icon(Icons.refresh),
            label: const Text('Réinitialiser'),
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
              _CampaignContextCard(
                referential: widget.referential,
                campaign: _campaign,
                canEdit: canEdit,
                onEditInformation: _editCampaignInformation,
              ),
              const SizedBox(height: 12),
              _ScoreCard(
                  summary: summary, justificationCount: _justificationCount),
              const SizedBox(height: 12),
              _LocalPersistenceCard(
                isLoading: _isLoadingAnswers,
                isSaving: _isSavingAnswers,
                message: _localStatusMessage,
              ),
              const SizedBox(height: 12),
              if (_isLoadingAnswers)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                for (final entry in criteriaByPillar.entries)
                  _PillarAssessmentCard(
                    pillar: entry.key,
                    criteria: entry.value,
                    criterionAnswers: _criterionAnswers,
                    answers: answers,
                    summary: _scoringService.computeSummaryForPillar(
                      widget.referential,
                      entry.key.id,
                      answers,
                    ),
                    canEdit: canEdit,
                    onAnswerChanged: _setAnswer,
                    onJustificationChanged: _setJustification,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampaignContextCard extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final bool canEdit;
  final VoidCallback onEditInformation;

  const _CampaignContextCard({
    required this.referential,
    required this.campaign,
    required this.canEdit,
    required this.onEditInformation,
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
            const Icon(Icons.folder_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(campaign.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Campagne locale · Référentiel ${referential.version}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(campaign.status.label)),
                      if (campaign.isReadOnly)
                        const Chip(
                          avatar: Icon(Icons.lock_outline, size: 18),
                          label: Text('Lecture seule'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(campaign.status.helperText,
                      style: theme.textTheme.bodySmall),
                  if (campaign.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(campaign.description),
                  ],
                  const SizedBox(height: 10),
                  _CampaignInfoRows(campaign: campaign),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: canEdit ? onEditInformation : null,
                      icon: const Icon(Icons.edit_note_outlined),
                      label:
                          const Text('Modifier les informations de campagne'),
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

class _CampaignInfoRows extends StatelessWidget {
  final LocalCampaign campaign;

  const _CampaignInfoRows({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final info = campaign.information;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.dns_outlined, size: 18),
          label: Text(info.systemName.trim().isEmpty
              ? 'SI non renseigné'
              : 'SI : ${info.systemName}'),
        ),
        Chip(
          avatar: const Icon(Icons.person_outline, size: 18),
          label: Text(_projectDirectorLabel(info)),
        ),
      ],
    );
  }

  String _projectDirectorLabel(CampaignInformation info) {
    final name = info.projectDirectorFullName;
    final email = info.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return 'Directeur : $name <$email>';
    }
    if (name.isNotEmpty) {
      return 'Directeur : $name';
    }
    if (email.isNotEmpty) {
      return 'Directeur : $email';
    }
    return 'Directeur projet non renseigné';
  }
}

class _CampaignInformationFormResult {
  final String name;
  final String description;
  final CampaignInformation information;

  const _CampaignInformationFormResult({
    required this.name,
    required this.description,
    required this.information,
  });
}

class _CampaignInformationDialog extends StatefulWidget {
  final LocalCampaign campaign;

  const _CampaignInformationDialog({required this.campaign});

  @override
  State<_CampaignInformationDialog> createState() =>
      _CampaignInformationDialogState();
}

class _CampaignInformationDialogState
    extends State<_CampaignInformationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _systemNameController;
  late final TextEditingController _systemDescriptionController;
  late final TextEditingController _projectDirectorFirstNameController;
  late final TextEditingController _projectDirectorLastNameController;
  late final TextEditingController _projectDirectorEmailController;

  @override
  void initState() {
    super.initState();
    final campaign = widget.campaign;
    final info = campaign.information;
    _nameController = TextEditingController(text: campaign.name);
    _descriptionController = TextEditingController(text: campaign.description);
    _systemNameController = TextEditingController(text: info.systemName);
    _systemDescriptionController =
        TextEditingController(text: info.systemDescription);
    _projectDirectorFirstNameController =
        TextEditingController(text: info.projectDirectorFirstName);
    _projectDirectorLastNameController =
        TextEditingController(text: info.projectDirectorLastName);
    _projectDirectorEmailController =
        TextEditingController(text: info.projectDirectorEmail);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _systemNameController.dispose();
    _systemDescriptionController.dispose();
    _projectDirectorFirstNameController.dispose();
    _projectDirectorLastNameController.dispose();
    _projectDirectorEmailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(
      _CampaignInformationFormResult(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        information: CampaignInformation(
          systemName: _systemNameController.text.trim(),
          systemDescription: _systemDescriptionController.text.trim(),
          projectDirectorFirstName:
              _projectDirectorFirstNameController.text.trim(),
          projectDirectorLastName:
              _projectDirectorLastNameController.text.trim(),
          projectDirectorEmail: _projectDirectorEmailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Informations de campagne'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Campagne',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
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
                    hintText:
                        'Périmètre, contexte ou objectif de l’évaluation.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Système d’information concerné',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _systemNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du système d’information',
                    hintText: 'Ex. SI Facturation',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Le nom du SI est obligatoire.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _systemDescriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Description du système d’information',
                    hintText:
                        'Fonction métier supportée, criticité, principaux composants ou dépendances.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'La description du SI est obligatoire.'
                      : null,
                ),
                const SizedBox(height: 18),
                Text('Directeur de projet',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _projectDirectorFirstNameController,
                        decoration: const InputDecoration(
                          labelText: 'Prénom',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Prénom obligatoire.'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _projectDirectorLastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nom',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nom obligatoire.'
                                : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _projectDirectorEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'prenom.nom@entreprise.fr',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Email obligatoire.';
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Email invalide.';
                    }
                    return null;
                  },
                ),
              ],
            ),
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
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final IrnScoreSummary summary;
  final int justificationCount;

  const _ScoreCard({required this.summary, required this.justificationCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = summary.officialScore;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Score officiel R / NR',
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      const Text(
                        'Calcul local : R / (R + NR). Les critères non cotés sont exclus du score.',
                      ),
                    ],
                  ),
                ),
                Text(
                  summary.formattedOfficialScore,
                  style: theme.textTheme.headlineMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: score == null ? 0 : score / 100),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Critères : ${summary.totalCriteria}')),
                Chip(label: Text('Cotés : ${summary.answeredCriteria}')),
                Chip(label: Text('R : ${summary.resilientCriteria}')),
                Chip(label: Text('NR : ${summary.nonResilientCriteria}')),
                Chip(label: Text('N.C. : ${summary.notAnsweredCriteria}')),
                Chip(label: Text('Justifications : $justificationCount')),
                Chip(
                    label: Text(
                        'Complétude : ${(summary.completionRate * 100).toStringAsFixed(0)} %')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalPersistenceCard extends StatelessWidget {
  final bool isLoading;
  final bool isSaving;
  final String? message;

  const _LocalPersistenceCard({
    required this.isLoading,
    required this.isSaving,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = isLoading || isSaving ? Icons.sync : Icons.save_outlined;
    final label = message ?? 'Sauvegarde locale prête.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (isLoading || isSaving)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillarAssessmentCard extends StatelessWidget {
  final IrnPillar pillar;
  final List<IrnCriterion> criteria;
  final Map<String, CriterionAnswer> criterionAnswers;
  final Map<String, IrnAnswer> answers;
  final IrnScoreSummary summary;
  final bool canEdit;
  final void Function(IrnCriterion criterion, IrnAnswer answer) onAnswerChanged;
  final void Function(IrnCriterion criterion, String justification)
      onJustificationChanged;

  const _PillarAssessmentCard({
    required this.pillar,
    required this.criteria,
    required this.criterionAnswers,
    required this.answers,
    required this.summary,
    required this.canEdit,
    required this.onAnswerChanged,
    required this.onJustificationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final justificationCount = criteria
        .where((criterion) =>
            criterionAnswers[criterion.id]?.justification.trim().isNotEmpty ??
            false)
        .length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Text('${pillar.code} — ${pillar.label}'),
        subtitle: Text(
          '${summary.answeredCriteria}/${summary.totalCriteria} coté(s) · '
          '$justificationCount justification(s) · Score : ${summary.formattedOfficialScore}',
        ),
        children: [
          for (final criterion in criteria)
            _CriterionAnswerTile(
              criterion: criterion,
              answer: answers[criterion.id] ?? IrnAnswer.notAnswered,
              justification:
                  criterionAnswers[criterion.id]?.justification ?? '',
              canEdit: canEdit,
              onAnswerChanged: (answer) => onAnswerChanged(criterion, answer),
              onJustificationChanged: (justification) =>
                  onJustificationChanged(criterion, justification),
            ),
        ],
      ),
    );
  }
}

class _CriterionAnswerTile extends StatelessWidget {
  final IrnCriterion criterion;
  final IrnAnswer answer;
  final String justification;
  final bool canEdit;
  final ValueChanged<IrnAnswer> onAnswerChanged;
  final ValueChanged<String> onJustificationChanged;

  const _CriterionAnswerTile({
    required this.criterion,
    required this.answer,
    required this.justification,
    required this.canEdit,
    required this.onAnswerChanged,
    required this.onJustificationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasJustification = justification.trim().isNotEmpty;
    final canJustify =
        answer == IrnAnswer.resilient || answer == IrnAnswer.nonResilient;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${criterion.code} — ${criterion.label}',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text('Portée : ${criterion.scope.label}'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final option in IrnAnswer.values)
                        ChoiceChip(
                          label: Text(option.label),
                          tooltip: option.longLabel,
                          selected: answer == option,
                          onSelected:
                              canEdit ? (_) => onAnswerChanged(option) : null,
                        ),
                    ],
                  ),
                ],
              ),
              if (canJustify) ...[
                const SizedBox(height: 8),
                if (hasJustification)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Text(
                      justification.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Text(
                    'Aucune justification renseignée.',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: canEdit
                        ? () => _openJustificationDialog(context)
                        : null,
                    icon: Icon(hasJustification
                        ? Icons.edit_note
                        : Icons.note_add_outlined),
                    label: Text(hasJustification
                        ? 'Modifier la justification'
                        : 'Ajouter une justification'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openJustificationDialog(BuildContext context) async {
    final controller = TextEditingController(text: justification);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Justification — ${criterion.code}'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Justification / commentaire',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              hintText:
                  'Explique la réponse, cite une preuve, une hypothèse ou un point à vérifier.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Effacer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) {
      return;
    }
    onJustificationChanged(result);
  }
}
