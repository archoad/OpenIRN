import 'package:flutter/material.dart';

import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import 'widgets/pillar_radar_chart.dart';
import '../common/openirn_app_bar.dart';

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
    final pillarSummaries = scoringService.computeSummariesByPillar(
      referential,
      answers,
    );
    final scopeSummaries = scoringService.computeSummariesByScope(
      referential,
      answers,
    );
    final weakestPillars = _rankedPillars(
      pillarSummaries,
      ascending: true,
    ).take(3).toList();
    final strongestPillars = _rankedPillars(
      pillarSummaries,
      ascending: false,
    ).take(3).toList();
    final radarData = _radarData(pillarSummaries);

    return Scaffold(
      appBar: OpenIrnAppBar(title: 'Synthèse — ${campaign.name}'),
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
              _IrnIndicatorBoardCard(
                globalSummary: globalSummary,
                pillarSummaries: pillarSummaries,
              ),
              const SizedBox(height: 12),
              _PillarRadarCard(data: radarData),
              const SizedBox(height: 12),
              const _SectionTitle(
                title: 'Score par pilier',
                subtitle: 'Lecture simple : R / (R + NR), hors critères N.C.',
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
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
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
          score: entry.value.openIrnRnrScore,
          completionRate: entry.value.completionRate,
        ),
    ];
  }

  List<MapEntry<IrnPillar, IrnScoreSummary>> _rankedPillars(
    Map<IrnPillar, IrnScoreSummary> summaries, {
    required bool ascending,
  }) {
    final entries = summaries.entries
        .where((entry) => entry.value.openIrnRnrScore != null)
        .toList(growable: false);

    final sorted = entries.toList()
      ..sort((a, b) {
        final left = a.value.openIrnRnrScore ?? 0;
        final right = b.value.openIrnRnrScore ?? 0;
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
                  Text(
                    campaign.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text('Campagne · ${referential.id} · ${referential.version}'),
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
    final score = summary.openIrnRnrScore;

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
                      Text('Score IRN', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      const Text(
                        'Score non pondéré R / (R + NR), basé sur les critères cotés du référentiel.',
                      ),
                    ],
                  ),
                ),
                Text(
                  summary.formattedOpenIrnRnrScore,
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
                Chip(
                  label: Text(
                    'Complétude : ${(summary.completionRate * 100).toStringAsFixed(0)} %',
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

class _InterpretationCard extends StatelessWidget {
  final IrnScoreSummary summary;

  const _InterpretationCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = summary.openIrnRnrScore;
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

class _IrnIndicatorBoardCard extends StatelessWidget {
  final IrnScoreSummary globalSummary;
  final Map<IrnPillar, IrnScoreSummary> pillarSummaries;

  const _IrnIndicatorBoardCard({
    required this.globalSummary,
    required this.pillarSummaries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pillarEntries = pillarSummaries.entries.toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.grid_view_rounded),
                const SizedBox(width: 8),
                Text('Indicateurs IRN', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Détail du score global et de chaque pilier sur 100.'),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GlobalIndicatorTile(summary: globalSummary),
                      const SizedBox(height: 12),
                      _PillarIndicatorGrid(entries: pillarEntries),
                    ],
                  );
                }

                const boardGap = 16.0;
                const gridSpacing = 12.0;
                const gridColumns = 4;
                const gridRows = 2;
                const gridChildAspectRatio = 1.0;
                final boardHeight = _wideIndicatorBoardHeight(
                  availableWidth: constraints.maxWidth,
                  gap: boardGap,
                  gridSpacing: gridSpacing,
                  gridColumns: gridColumns,
                  gridRows: gridRows,
                  gridChildAspectRatio: gridChildAspectRatio,
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox.square(
                      dimension: boardHeight,
                      child: _GlobalIndicatorTile(summary: globalSummary),
                    ),
                    const SizedBox(width: boardGap),
                    Expanded(
                      child: _PillarIndicatorGrid(entries: pillarEntries),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const _IndicatorLegend(),
          ],
        ),
      ),
    );
  }
}

double _wideIndicatorBoardHeight({
  required double availableWidth,
  required double gap,
  required double gridSpacing,
  required int gridColumns,
  required int gridRows,
  required double gridChildAspectRatio,
}) {
  final rowToColumnFactor = gridRows / (gridColumns * gridChildAspectRatio);
  final gridSpacingWidth = (gridColumns - 1) * gridSpacing;
  final gridSpacingHeight = (gridRows - 1) * gridSpacing;
  return ((rowToColumnFactor * (availableWidth - gap - gridSpacingWidth)) +
          gridSpacingHeight) /
      (1 + rowToColumnFactor);
}

class _GlobalIndicatorTile extends StatelessWidget {
  final IrnScoreSummary summary;

  const _GlobalIndicatorTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: _IndicatorTile(
        title: 'Score global',
        score: summary.openIrnRnrScore,
        compactTitle: false,
        icon: Icons.speed_rounded,
        subtitle:
            '${summary.answeredCriteria}/${summary.totalCriteria} coté(s) · Complétude ${(summary.completionRate * 100).toStringAsFixed(0)} %',
      ),
    );
  }
}

class _PillarIndicatorGrid extends StatelessWidget {
  final List<MapEntry<IrnPillar, IrnScoreSummary>> entries;

  const _PillarIndicatorGrid({required this.entries});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 520 ? 4 : 2;
        return GridView.builder(
          itemCount: entries.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 4 ? 1.0 : 0.95,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _IndicatorTile(
              title: _pillarThemeLabel(entry.key),
              score: entry.value.openIrnRnrScore,
              badge: entry.key.code,
              compactTitle: true,
              icon: _pillarIcon(entry.key),
              subtitle:
                  'R ${entry.value.resilientCriteria} · NR ${entry.value.nonResilientCriteria}',
            );
          },
        );
      },
    );
  }
}

class _IndicatorTile extends StatelessWidget {
  final String title;
  final String? badge;
  final double? score;
  final String subtitle;
  final bool compactTitle;
  final IconData icon;

  const _IndicatorTile({
    required this.title,
    required this.score,
    required this.subtitle,
    required this.compactTitle,
    required this.icon,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _scoreTileColor(score);
    final foregroundColor = _scoreTileForegroundColor(backgroundColor);
    final theme = Theme.of(context);
    final tilePadding = compactTitle ? 12.0 : 14.0;
    final iconSize = compactTitle ? 19.0 : 32.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(tilePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: foregroundColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const Spacer(),
                _IndicatorIcon(
                  icon: icon,
                  color: foregroundColor,
                  size: iconSize,
                  compact: compactTitle,
                ),
              ],
            ),
            SizedBox(height: compactTitle ? 6 : 12),
            Text(
              title,
              maxLines: compactTitle ? 2 : 2,
              overflow: TextOverflow.ellipsis,
              style:
                  (compactTitle
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    score == null ? '—' : score!.round().toString(),
                    style:
                        (compactTitle
                                ? theme.textTheme.headlineMedium
                                : theme.textTheme.displayMedium)
                            ?.copyWith(
                              color: foregroundColor,
                              fontWeight: FontWeight.w800,
                              height: 0.95,
                            ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    '/100',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              maxLines: compactTitle ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foregroundColor.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndicatorIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool compact;

  const _IndicatorIcon({
    required this.icon,
    required this.color,
    required this.size,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 30 : 48,
      height: compact ? 30 : 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

class _IndicatorLegend extends StatelessWidget {
  const _IndicatorLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = const [
      _IndicatorLegendEntry(label: '80–100', description: 'Faible', score: 90),
      _IndicatorLegendEntry(label: '60–79', description: 'Modéré', score: 70),
      _IndicatorLegendEntry(label: '40–59', description: 'Haut', score: 50),
      _IndicatorLegendEntry(label: '0–39', description: 'Critique', score: 20),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Légende', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final entry in entries) _IndicatorLegendChip(entry: entry),
            const _IndicatorLegendChip(
              entry: _IndicatorLegendEntry(
                label: '—',
                description: 'Non coté',
                score: null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IndicatorLegendChip extends StatelessWidget {
  final _IndicatorLegendEntry entry;

  const _IndicatorLegendChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _scoreTileColor(entry.score?.toDouble());
    final foregroundColor = _scoreTileForegroundColor(color);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            entry.description,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor.withValues(alpha: 0.80),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndicatorLegendEntry {
  final String label;
  final String description;
  final int? score;

  const _IndicatorLegendEntry({
    required this.label,
    required this.description,
    required this.score,
  });
}

IconData _pillarIcon(IrnPillar pillar) {
  switch (pillar.code.toUpperCase()) {
    case 'RES-1':
      return Icons.flag_rounded;
    case 'RES-2':
      return Icons.account_balance_rounded;
    case 'RES-3':
      return Icons.storage_rounded;
    case 'RES-4':
      return Icons.settings_suggest_rounded;
    case 'RES-5':
      return Icons.hub_rounded;
    case 'RES-6':
      return Icons.memory_rounded;
    case 'RES-7':
      return Icons.shield_rounded;
    case 'RES-8':
      return Icons.eco_rounded;
    default:
      return Icons.widgets_rounded;
  }
}

String _pillarThemeLabel(IrnPillar pillar) {
  var label = pillar.label.trim();
  label = label.replaceAll(
    RegExp(r'\brésilience\b\s*(?:&\s*)?', caseSensitive: false),
    '',
  );
  label = label.replaceAll(RegExp(r'^\s*&\s*'), '');
  label = label.replaceAll(RegExp(r'\s*&\s*$'), '');
  label = label.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  if (label.isEmpty) {
    return pillar.label;
  }
  return label[0].toUpperCase() + label.substring(1);
}

Color _scoreTileColor(double? score) {
  if (score == null) {
    return const Color(0xFFF2F4F7);
  }

  final bounded = score.clamp(0, 100).toDouble();
  if (bounded >= 80) {
    return const Color(0xFF2E7D32); // vert
  }
  if (bounded >= 60) {
    return const Color(0xFFFFCE00); // jaune
  }
  if (bounded >= 40) {
    return const Color(0xFFEF6C00); // orange
  }
  return const Color(0xFFC62828); // rouge
}

Color _scoreTileForegroundColor(Color backgroundColor) {
  return backgroundColor.computeLuminance() < 0.45
      ? Colors.white
      : const Color(0xFF1F2937);
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
                Text('Radar IRN', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Visualisation du score IRN par pilier. Les critères N.C. sont exclus du score et aucune pondération n’est appliquée.',
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
    final score = summary.openIrnRnrScore;

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
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle),
                    ],
                  ),
                ),
                Text(
                  summary.formattedOpenIrnRnrScore,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                  trailing: Text(entry.value.formattedOpenIrnRnrScore),
                ),
          ],
        ),
      ),
    );
  }
}
