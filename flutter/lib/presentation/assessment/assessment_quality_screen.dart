import 'package:flutter/material.dart';

import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/assessment_quality_service.dart';

class AssessmentQualityScreen extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;

  const AssessmentQualityScreen({
    required this.referential,
    required this.campaign,
    required this.criterionAnswers,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final report = const AssessmentQualityService().buildReport(
      referential: referential,
      criterionAnswers: criterionAnswers,
      campaign: campaign,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrôle qualité'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _QualityHeaderCard(
                campaign: campaign,
                referential: referential,
                report: report,
              ),
              const SizedBox(height: 12),
              _CampaignInformationQualityCard(
                campaign: campaign,
                missingInformation: report.missingCampaignInformation,
              ),
              const SizedBox(height: 12),
              _QualityProgressCard(report: report),
              const SizedBox(height: 12),
              _MissingAnswersCard(criteria: report.missingAnswers),
              const SizedBox(height: 12),
              _MissingJustificationsCard(issues: report.missingJustifications),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityHeaderCard extends StatelessWidget {
  final LocalCampaign campaign;
  final IrnReferential referential;
  final AssessmentQualityReport report;

  const _QualityHeaderCard({
    required this.campaign,
    required this.referential,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = report.isReadyForReview
        ? Icons.verified_outlined
        : Icons.rule_folder_outlined;
    final title = report.isReadyForReview
        ? 'Campagne prête pour revue'
        : 'Campagne à compléter';
    final message = report.isReadyForReview
        ? 'Les informations de campagne sont complètes, tous les critères actifs sont cotés et chaque réponse R / NR dispose d’une justification.'
        : 'Complète les informations de campagne, les critères non cotés et les justifications avant revue ou export de référence.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(message),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Campagne : ${campaign.name}')),
                      Chip(label: Text('Référentiel : ${referential.version}')),
                      Chip(label: Text('Critères : ${report.totalCriteria}')),
                      Chip(
                          label: Text(
                              'Infos campagne manquantes : ${report.missingCampaignInformationCount}')),
                      Chip(
                          label:
                              Text('Non cotés : ${report.missingAnswerCount}')),
                      Chip(
                          label: Text(
                              'Justifications manquantes : ${report.missingJustificationCount}')),
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
}

class _CampaignInformationQualityCard extends StatelessWidget {
  final LocalCampaign campaign;
  final List<CampaignInformationIssue> missingInformation;

  const _CampaignInformationQualityCard({
    required this.campaign,
    required this.missingInformation,
  });

  @override
  Widget build(BuildContext context) {
    final info = campaign.information;
    final isComplete = missingInformation.isEmpty;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: !isComplete,
        leading:
            Icon(isComplete ? Icons.check_circle_outline : Icons.info_outline),
        title: Text(
            'Informations de campagne (${isComplete ? 'complètes' : '${missingInformation.length} manquante(s)'})'),
        subtitle: const Text(
            'Ces éléments identifient le système évalué et le directeur de projet.'),
        children: [
          ListTile(
            dense: true,
            title: const Text('Système d’information'),
            subtitle: Text(info.systemName.trim().isEmpty
                ? 'Non renseigné'
                : info.systemName),
          ),
          ListTile(
            dense: true,
            title: const Text('Description du système d’information'),
            subtitle: Text(info.systemDescription.trim().isEmpty
                ? 'Non renseignée'
                : info.systemDescription),
          ),
          ListTile(
            dense: true,
            title: const Text('Directeur de projet'),
            subtitle: Text(_projectDirectorLabel(info)),
          ),
          if (missingInformation.isNotEmpty)
            for (final issue in missingInformation)
              ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(issue.label),
                subtitle: const Text(
                    'Champ obligatoire pour passer la campagne en revue.'),
              ),
        ],
      ),
    );
  }

  String _projectDirectorLabel(CampaignInformation info) {
    final name = info.projectDirectorFullName;
    final email = info.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name <$email>';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return 'Non renseigné';
  }
}

class _QualityProgressCard extends StatelessWidget {
  final AssessmentQualityReport report;

  const _QualityProgressCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progression qualité',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _ProgressLine(
              label: 'Informations de campagne',
              value: report.campaignInformationCompletionRate,
              trailing: '${5 - report.missingCampaignInformationCount}/5',
            ),
            const SizedBox(height: 14),
            _ProgressLine(
              label: 'Critères cotés',
              value: report.answerCompletionRate,
              trailing: '${report.answeredCriteria}/${report.totalCriteria}',
            ),
            const SizedBox(height: 14),
            _ProgressLine(
              label: 'Réponses justifiées',
              value: report.justificationCompletionRate,
              trailing:
                  '${report.justifiedCriteria}/${report.answeredCriteria}',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final String label;
  final double value;
  final String trailing;

  const _ProgressLine({
    required this.label,
    required this.value,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (value * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('$percentage % · $trailing'),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: value),
      ],
    );
  }
}

class _MissingAnswersCard extends StatelessWidget {
  final List<IrnCriterion> criteria;

  const _MissingAnswersCard({required this.criteria});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: criteria.isNotEmpty,
        leading: const Icon(Icons.radio_button_unchecked),
        title: Text('Critères non cotés (${criteria.length})'),
        subtitle: const Text(
            'Ces critères sont encore en N.C. et ne contribuent pas au score.'),
        children: criteria.isEmpty
            ? const [
                ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Tous les critères actifs sont cotés.'),
                ),
              ]
            : [
                for (final criterion in criteria)
                  _CriterionQualityTile(
                    criterion: criterion,
                    trailing: 'N.C.',
                  ),
              ],
      ),
    );
  }
}

class _MissingJustificationsCard extends StatelessWidget {
  final List<AssessmentQualityIssue> issues;

  const _MissingJustificationsCard({required this.issues});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: issues.isNotEmpty,
        leading: const Icon(Icons.edit_note_outlined),
        title: Text('Justifications manquantes (${issues.length})'),
        subtitle: const Text('Chaque réponse R / NR doit être documentée.'),
        children: issues.isEmpty
            ? const [
                ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Toutes les réponses cotées sont justifiées.'),
                ),
              ]
            : [
                for (final issue in issues)
                  _CriterionQualityTile(
                    criterion: issue.criterion,
                    trailing: issue.answer.label,
                  ),
              ],
      ),
    );
  }
}

class _CriterionQualityTile extends StatelessWidget {
  final IrnCriterion criterion;
  final String trailing;

  const _CriterionQualityTile({
    required this.criterion,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text('${criterion.code} — ${criterion.label}'),
      subtitle: Text(
          'Pilier ${criterion.pillarId} · Portée : ${criterion.scope.label}'),
      trailing: Chip(label: Text(trailing)),
    );
  }
}
