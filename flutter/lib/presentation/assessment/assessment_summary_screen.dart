import 'package:flutter/material.dart';

import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import 'widgets/pillar_radar_chart.dart';

class AssessmentSummaryScreen extends StatelessWidget {
  final IrnReferential referential;
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;

  const AssessmentSummaryScreen({
    required this.referential,
    required this.campaign,
    required this.criterionAnswers,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const scoringService = OfficialRnrScoringService();
    final answers = _answersFromCriterionAnswers(criterionAnswers);
    final globalSummary = scoringService.computeSummary(referential, answers);
    final pillarSummaries =
        scoringService.computeSummariesByPillar(referential, answers);
    final scopeSummaries =
        scoringService.computeSummariesByScope(referential, answers);
    final weakestPillars =
        _rankedPillars(pillarSummaries, ascending: true).take(3).toList();
    final strongestPillars =
        _rankedPillars(pillarSummaries, ascending: false).take(3).toList();
    final radarData = _radarData(pillarSummaries);

    return Scaffold(
      appBar: AppBar(
        title: Text('Synthèse — ${campaign.name}'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CampaignSummaryHeader(
                campaign: campaign,
                referential: referential,
              ),
              const SizedBox(height: 12),
              _GlobalSummaryCard(summary: globalSummary),
              const SizedBox(height: 12),
              _InterpretationCard(summary: globalSummary),
              const SizedBox(height: 12),
              _PillarRadarCard(data: radarData),
              const SizedBox(height: 12),
              const _SectionTitle(
                title: 'Score par pilier',
                subtitle:
                    'Lecture officielle simple : R / (R + NR), hors critères N.C.',
              ),
              const SizedBox(height: 8),
              for (final entry in pillarSummaries.entries)
                _PillarScoreCard(pillar: entry.key, summary: entry.value),
              const SizedBox(height: 12),
              const _SectionTitle(
                title: 'Répartition par portée',
                subtitle:
                    'Utile pour distinguer les critères organisationnels et les critères d’actif numérique.',
              ),
              const SizedBox(height: 8),
              for (final entry in scopeSummaries.entries)
                _ScopeScoreCard(scope: entry.key, summary: entry.value),
              const SizedBox(height: 12),
              _RankedPillarsCard(
                title: 'Points forts provisoires',
                icon: Icons.trending_up,
                entries: strongestPillars,
                emptyMessage:
                    'Pas encore assez de critères cotés pour identifier les points forts.',
              ),
              const SizedBox(height: 12),
              _RankedPillarsCard(
                title: 'Points d’attention provisoires',
                icon: Icons.priority_high,
                entries: weakestPillars,
                emptyMessage:
                    'Pas encore assez de critères cotés pour identifier les points d’attention.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, IrnAnswer> _answersFromCriterionAnswers(
      Map<String, CriterionAnswer> criterionAnswers) {
    return <String, IrnAnswer>{
      for (final entry in criterionAnswers.entries)
        entry.key: entry.value.answer,
    };
  }

  List<PillarRadarDatum> _radarData(Map<IrnPillar, IrnScoreSummary> summaries) {
    return [
      for (final entry in summaries.entries)
        PillarRadarDatum(
          code: entry.key.code,
          label: entry.key.label,
          score: entry.value.officialScore,
          completionRate: entry.value.completionRate,
        ),
    ];
  }

  List<MapEntry<IrnPillar, IrnScoreSummary>> _rankedPillars(
    Map<IrnPillar, IrnScoreSummary> summaries, {
    required bool ascending,
  }) {
    final entries = summaries.entries
        .where((entry) => entry.value.officialScore != null)
        .toList(growable: false);

    final sorted = entries.toList()
      ..sort((a, b) {
        final left = a.value.officialScore ?? 0;
        final right = b.value.officialScore ?? 0;
        return ascending ? left.compareTo(right) : right.compareTo(left);
      });

    return sorted;
  }
}

class _CampaignSummaryHeader extends StatelessWidget {
  final LocalCampaign campaign;
  final IrnReferential referential;

  const _CampaignSummaryHeader({
    required this.campaign,
    required this.referential,
  });

  @override
  Widget build(BuildContext context) {
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
                  Text(campaign.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                      'Campagne locale · ${referential.id} · ${referential.version}'),
                  if (campaign.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(campaign.description),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalSummaryCard extends StatelessWidget {
  final IrnScoreSummary summary;

  const _GlobalSummaryCard({required this.summary});

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
                      Text('Score global officiel',
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      const Text(
                          'Moteur R / NR local, basé uniquement sur le référentiel officiel.'),
                    ],
                  ),
                ),
                Text(summary.formattedOfficialScore,
                    style: theme.textTheme.headlineMedium),
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

class _InterpretationCard extends StatelessWidget {
  final IrnScoreSummary summary;

  const _InterpretationCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = summary.officialScore;
    final completion = summary.completionRate;
    final interpretation = _interpret(score: score, completion: completion);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lecture rapide', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(interpretation),
                  const SizedBox(height: 8),
                  const Text(
                    'Cette synthèse reste indicative tant que le périmètre entreprise, les assets, les campagnes et les validations ne sont pas branchés.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _interpret({required double? score, required double completion}) {
    if (score == null) {
      return 'Aucun critère n’est encore coté. Commence par renseigner quelques réponses R / NR.';
    }
    if (completion < 0.5) {
      return 'Le score est encore fragile : moins de la moitié du référentiel est coté.';
    }
    if (score >= 80) {
      return 'Le niveau de résilience déclaré est élevé sur les critères cotés.';
    }
    if (score >= 60) {
      return 'Le niveau de résilience déclaré est intermédiaire, avec des points d’amélioration visibles.';
    }
    return 'Le niveau de résilience déclaré est faible sur les critères cotés : les critères NR doivent être analysés en priorité.';
  }
}

class _PillarRadarCard extends StatelessWidget {
  final List<PillarRadarDatum> data;

  const _PillarRadarCard({required this.data});

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
                const Icon(Icons.radar),
                const SizedBox(width: 8),
                Text('Radar des 8 piliers', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Visualisation du score R / (R + NR) par pilier. Les critères N.C. sont exclus du score.',
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final chart = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: PillarRadarChart(data: data),
                );
                final legend = _PillarRadarLegend(data: data);

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: chart),
                      const SizedBox(height: 12),
                      legend,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Center(child: chart)),
                    const SizedBox(width: 16),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarRadarLegend extends StatelessWidget {
  final List<PillarRadarDatum> data;

  const _PillarRadarLegend({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final datum in data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(datum.code, style: theme.textTheme.labelLarge),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(datum.label),
                      const SizedBox(height: 3),
                      LinearProgressIndicator(value: datum.normalizedScore),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: Text(
                    datum.formattedScore,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(subtitle),
        ],
      ),
    );
  }
}

class _PillarScoreCard extends StatelessWidget {
  final IrnPillar pillar;
  final IrnScoreSummary summary;

  const _PillarScoreCard({required this.pillar, required this.summary});

  @override
  Widget build(BuildContext context) {
    return _ScoreLineCard(
      title: '${pillar.code} — ${pillar.label}',
      subtitle:
          '${summary.answeredCriteria}/${summary.totalCriteria} coté(s) · R ${summary.resilientCriteria} · NR ${summary.nonResilientCriteria}',
      summary: summary,
    );
  }
}

class _ScopeScoreCard extends StatelessWidget {
  final CriterionScope scope;
  final IrnScoreSummary summary;

  const _ScopeScoreCard({required this.scope, required this.summary});

  @override
  Widget build(BuildContext context) {
    return _ScoreLineCard(
      title: scope.label,
      subtitle:
          '${summary.answeredCriteria}/${summary.totalCriteria} coté(s) · R ${summary.resilientCriteria} · NR ${summary.nonResilientCriteria}',
      summary: summary,
    );
  }
}

class _ScoreLineCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IrnScoreSummary summary;

  const _ScoreLineCard({
    required this.title,
    required this.subtitle,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final score = summary.officialScore;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle),
                    ],
                  ),
                ),
                Text(summary.formattedOfficialScore,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: score == null ? 0 : score / 100),
          ],
        ),
      ),
    );
  }
}

class _RankedPillarsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<MapEntry<IrnPillar, IrnScoreSummary>> entries;
  final String emptyMessage;

  const _RankedPillarsCard({
    required this.title,
    required this.icon,
    required this.entries,
    required this.emptyMessage,
  });

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
                Icon(icon),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text(emptyMessage)
            else
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${entry.key.code} — ${entry.key.label}'),
                  trailing: Text(entry.value.formattedOfficialScore),
                ),
          ],
        ),
      ),
    );
  }
}
