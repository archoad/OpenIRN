import 'package:flutter/material.dart';

import '../../l10n/openirn_localizations.dart';
import '../common/openirn_app_bar.dart';

class ScoringMethodScreen extends StatelessWidget {
  const ScoringMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Mode de calcul de la note IRN'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.functions_outlined, size: 34),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.tr(
                                'screen.scoring.main_title',
                                fallback:
                                    'Maturité IRN d’un système d’information',
                              ),
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr(
                          'screen.scoring.main_intro',
                          fallback:
                              'Un SI est évalué comme une composition d’actifs numériques. Chaque actif est noté sur les piliers RES, puis la note du SI est consolidée en tenant compte de la criticité de chaque actif.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _FormulaStepCard(
                title: context.tr(
                  'screen.scoring.step1.title',
                  fallback: '1 · Notation d’un actif',
                ),
                icon: Icons.checklist_rtl_outlined,
                children: [
                  Text(
                    context.tr(
                      'screen.scoring.step1.intro',
                      fallback:
                          'La maturité de chaque actif est évaluée selon la grille IRN :',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _ScoreScaleWrap(),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'screen.scoring.step1.nc',
                      fallback:
                          'N.C. signifie “Non concerné” : le critère est explicitement renseigné et compte dans la complétude, mais il est exclu du score.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FormulaStepCard(
                title: context.tr(
                  'screen.scoring.step2.title',
                  fallback: '2 · Pré-score E de chaque actif',
                ),
                icon: Icons.inventory_2_outlined,
                children: [
                  Text(
                    context.tr(
                      'screen.scoring.step2.p1',
                      fallback:
                          'Pour chaque actif, OpenIRN calcule d’abord un score par pilier RES à partir des critères cotés du pilier.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'screen.scoring.step2.p2',
                      fallback:
                          'Le pré-score E de l’actif est ensuite la moyenne géométrique des scores de piliers renseignés :',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _FormulaBox(
                    'E = EXP( MOYENNE( LN(score pilier RES) ) )',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'screen.scoring.step2.p3',
                      fallback:
                          'La moyenne géométrique pénalise naturellement les maillons faibles : un pilier très bas tire davantage la note de l’actif vers le bas qu’une moyenne arithmétique.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FormulaStepCard(
                title: context.tr(
                  'screen.scoring.step3.title',
                  fallback: '3 · Criticité D de l’actif',
                ),
                icon: Icons.priority_high_outlined,
                children: [
                  Text(
                    context.tr(
                      'screen.scoring.step3.p1',
                      fallback:
                          'Chaque actif porte une criticité D sur 4 niveaux. Cette criticité représente le poids de l’actif dans la résilience globale du SI.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          context.tr('criticality.1', fallback: '1 — standard'),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr('criticality.2', fallback: '2 — modérée'),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr('criticality.3', fallback: '3 — élevée'),
                        ),
                      ),
                      Chip(
                        label: Text(
                          context.tr('criticality.4', fallback: '4 — critique'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FormulaStepCard(
                title: context.tr(
                  'screen.scoring.step4.title',
                  fallback: '4 · Score de maturité du SI',
                ),
                icon: Icons.account_tree_outlined,
                children: [
                  Text(
                    context.tr(
                      'screen.scoring.step4.p1',
                      fallback:
                          'La note de maturité du SI est la moyenne géométrique pondérée des pré-scores E des actifs, avec D comme poids :',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _FormulaBox(
                    'Score SI = EXP( SOMME( D × LN(E) ) ÷ SOMME(D) )',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'screen.scoring.step4.p2',
                      fallback:
                          'Un actif critique mal noté pèse donc beaucoup plus fortement sur la note du SI qu’un actif peu critique. La formule traduit l’idée de chaîne de résilience : le maillon faible doit compter.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FormulaStepCard(
                title: context.tr(
                  'screen.scoring.step5.title',
                  fallback: '5 · Lecture dans OpenIRN',
                ),
                icon: Icons.insights_outlined,
                children: [
                  Text(
                    context.tr(
                      'screen.scoring.step5.p1',
                      fallback:
                          'Dans une campagne créée depuis un SI, le cartouche “Score IRN” affiche la maturité consolidée du SI. Les boutons d’actifs permettent de saisir séparément la grille IRN de chaque actif.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'screen.scoring.step5.p2',
                      fallback:
                          'Les critères non renseignés ne participent pas encore au score. La complétude reste donc indispensable pour interpréter correctement la note.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormulaStepCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _FormulaStepCard({
    required this.title,
    required this.icon,
    required this.children,
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
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FormulaBox extends StatelessWidget {
  final String formula;

  const _FormulaBox(this.formula);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SelectableText(
        formula,
        style: theme.textTheme.titleSmall?.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScoreScaleWrap extends StatelessWidget {
  const _ScoreScaleWrap();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          label: Text(
            context.tr('score.nc', fallback: 'N.C. — exclu du score'),
          ),
        ),
        Chip(
          label: Text(
            context.tr(
              'score.non_resilient',
              fallback: 'Non résilient — 10/100',
            ),
          ),
        ),
        Chip(
          label: Text(
            context.tr('score.intention', fallback: 'Intention — 25/100'),
          ),
        ),
        Chip(
          label: Text(context.tr('score.medium', fallback: 'Moyen — 50/100')),
        ),
        Chip(
          label: Text(
            context.tr('score.result', fallback: 'Résultat — 95/100'),
          ),
        ),
      ],
    );
  }
}
