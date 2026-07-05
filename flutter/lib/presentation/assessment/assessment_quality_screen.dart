import 'package:flutter/material.dart';

import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/assessment_quality_service.dart';
import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';

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
      appBar: OpenIrnAppBar(
        title: context.tr(
          'assessment.quality.title',
          fallback: 'Contrôle qualité',
        ),
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
        ? context.tr(
            'assessment.quality.ready_title',
            fallback: 'Campagne prête pour revue',
          )
        : context.tr(
            'assessment.quality.incomplete_title',
            fallback: 'Campagne à compléter',
          );
    final message = report.isReadyForReview
        ? context.tr(
            'assessment.quality.ready_message',
            fallback:
                'Les informations de campagne sont complètes, tous les critères actifs sont renseignés et chaque note IRN dispose d’une justification.',
          )
        : context.tr(
            'assessment.quality.incomplete_message',
            fallback:
                'Compléter les informations de campagne, les critères non renseignés et les justifications avant revue ou export de référence.',
          );

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
                      Chip(
                        label: Text(
                          context.tr(
                            'assessment.quality.chip.campaign',
                            fallback: 'Campagne : {name}',
                            values: {'name': campaign.name},
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr(
                            'assessment.quality.chip.referential',
                            fallback: 'Référentiel : {version}',
                            values: {'version': referential.version},
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr(
                            'assessment.quality.chip.criteria',
                            fallback: 'Critères : {count}',
                            values: {'count': report.totalCriteria},
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr(
                            'assessment.quality.chip.missing_campaign_info',
                            fallback: 'Infos campagne manquantes : {count}',
                            values: {
                              'count': report.missingCampaignInformationCount,
                            },
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr(
                            'assessment.quality.chip.missing_answers',
                            fallback: 'Non renseignés : {count}',
                            values: {'count': report.missingAnswerCount},
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr(
                            'assessment.quality.chip.missing_justifications',
                            fallback: 'Justifications manquantes : {count}',
                            values: {'count': report.missingJustificationCount},
                          ),
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
        leading: Icon(
          isComplete ? Icons.check_circle_outline : Icons.info_outline,
        ),
        title: Text(
          isComplete
              ? context.tr(
                  'assessment.quality.campaign_info.complete_title',
                  fallback: 'Informations de campagne (complètes)',
                )
              : context.tr(
                  'assessment.quality.campaign_info.missing_title',
                  fallback: 'Informations de campagne ({count} manquante(s))',
                  values: {'count': missingInformation.length},
                ),
        ),
        subtitle: Text(
          context.tr(
            'assessment.quality.campaign_info.subtitle',
            fallback:
                'Ces éléments identifient le système évalué et le directeur de projet.',
          ),
        ),
        children: [
          ListTile(
            dense: true,
            title: Text(
              context.tr(
                'inventory.information_system',
                fallback: 'Système d’information',
              ),
            ),
            subtitle: Text(
              info.systemName.trim().isEmpty
                  ? context.tr(
                      'common.not_provided_masculine',
                      fallback: 'Non renseigné',
                    )
                  : info.systemName,
            ),
          ),
          ListTile(
            dense: true,
            title: Text(
              context.tr(
                'assessment.quality.system_description',
                fallback: 'Description du système d’information',
              ),
            ),
            subtitle: Text(
              info.systemDescription.trim().isEmpty
                  ? context.tr(
                      'common.not_provided_feminine',
                      fallback: 'Non renseignée',
                    )
                  : info.systemDescription,
            ),
          ),
          ListTile(
            dense: true,
            title: Text(
              context.tr(
                'campaign.project_director',
                fallback: 'Directeur de projet',
              ),
            ),
            subtitle: Text(_projectDirectorLabel(info)),
          ),
          if (missingInformation.isNotEmpty)
            for (final issue in missingInformation)
              ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(issue.label),
                subtitle: Text(
                  context.tr(
                    'assessment.quality.required_for_review',
                    fallback:
                        'Champ obligatoire pour passer la campagne en revue.',
                  ),
                ),
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
    return OpenIrnLocalizations.instance.tr(
      'common.not_provided_masculine',
      fallback: 'Non renseigné',
    );
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
            Text(
              context.tr(
                'assessment.quality.progress.title',
                fallback: 'Progression qualité',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _ProgressLine(
              label: context.tr(
                'assessment.quality.progress.campaign_info',
                fallback: 'Informations de campagne',
              ),
              value: report.campaignInformationCompletionRate,
              trailing: '${5 - report.missingCampaignInformationCount}/5',
            ),
            const SizedBox(height: 14),
            _ProgressLine(
              label: context.tr(
                'assessment.quality.progress.scored_criteria',
                fallback: 'Critères cotés',
              ),
              value: report.answerCompletionRate,
              trailing: '${report.answeredCriteria}/${report.totalCriteria}',
            ),
            const SizedBox(height: 14),
            _ProgressLine(
              label: context.tr(
                'assessment.quality.progress.justified_answers',
                fallback: 'Réponses justifiées',
              ),
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
        title: Text(
          context.tr(
            'assessment.quality.missing_answers.title',
            fallback: 'Critères non renseignés ({count})',
            values: {'count': criteria.length},
          ),
        ),
        subtitle: Text(
          context.tr(
            'assessment.quality.missing_answers.subtitle',
            fallback:
                'Ces critères ne disposent pas encore d’une note IRN ou d’un statut N.C.',
          ),
        ),
        children: criteria.isEmpty
            ? [
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(
                    context.tr(
                      'assessment.quality.missing_answers.empty',
                      fallback: 'Tous les critères actifs sont cotés.',
                    ),
                  ),
                ),
              ]
            : [
                for (final criterion in criteria)
                  _CriterionQualityTile(criterion: criterion, trailing: 'N.C.'),
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
        title: Text(
          context.tr(
            'assessment.quality.missing_justifications.title',
            fallback: 'Justifications manquantes ({count})',
            values: {'count': issues.length},
          ),
        ),
        subtitle: Text(
          context.tr(
            'assessment.quality.missing_justifications.subtitle',
            fallback: 'Chaque note IRN doit être documentée.',
          ),
        ),
        children: issues.isEmpty
            ? [
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(
                    context.tr(
                      'assessment.quality.missing_justifications.empty',
                      fallback: 'Toutes les réponses cotées sont justifiées.',
                    ),
                  ),
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
        context.tr(
          'assessment.quality.criterion_scope',
          fallback: 'Pilier {pillar} · Portée : {scope}',
          values: {
            'pillar': criterion.pillarId,
            'scope': criterion.scope.label,
          },
        ),
      ),
      trailing: Chip(label: Text(trailing)),
    );
  }
}
