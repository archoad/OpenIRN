import 'package:flutter/material.dart';

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
                              'Maturité IRN d’un système d’information',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Un SI est évalué comme une composition d’actifs numériques. Chaque actif est noté sur les piliers RES, puis la note du SI est consolidée en tenant compte de la criticité de chaque actif.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _FormulaStepCard(
                title: '1 · Notation d’un actif',
                icon: Icons.checklist_rtl_outlined,
                children: [
                  Text(
                    'La maturité de chaque actif est évaluée selon la grille IRN :',
                  ),
                  SizedBox(height: 8),
                  _ScoreScaleWrap(),
                  SizedBox(height: 8),
                  Text(
                    'N.C. signifie “Non concerné” : le critère est explicitement renseigné et compte dans la complétude, mais il est exclu du score.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _FormulaStepCard(
                title: '2 · Pré-score E de chaque actif',
                icon: Icons.inventory_2_outlined,
                children: [
                  Text(
                    'Pour chaque actif, OpenIRN calcule d’abord un score par pilier RES à partir des critères cotés du pilier.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Le pré-score E de l’actif est ensuite la moyenne géométrique des scores de piliers renseignés :',
                  ),
                  SizedBox(height: 8),
                  _FormulaBox('E = EXP( MOYENNE( LN(score pilier RES) ) )'),
                  SizedBox(height: 8),
                  Text(
                    'La moyenne géométrique pénalise naturellement les maillons faibles : un pilier très bas tire davantage la note de l’actif vers le bas qu’une moyenne arithmétique.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _FormulaStepCard(
                title: '3 · Criticité D de l’actif',
                icon: Icons.priority_high_outlined,
                children: [
                  Text(
                    'Chaque actif porte une criticité D sur 4 niveaux. Cette criticité représente le poids de l’actif dans la résilience globale du SI.',
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('1 — standard')),
                      Chip(label: Text('2 — modérée')),
                      Chip(label: Text('3 — élevée')),
                      Chip(label: Text('4 — critique')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _FormulaStepCard(
                title: '4 · Score de maturité du SI',
                icon: Icons.account_tree_outlined,
                children: [
                  Text(
                    'La note de maturité du SI est la moyenne géométrique pondérée des pré-scores E des actifs, avec D comme poids :',
                  ),
                  SizedBox(height: 8),
                  _FormulaBox(
                    'Score SI = EXP( SOMME( D × LN(E) ) ÷ SOMME(D) )',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Un actif critique mal noté pèse donc beaucoup plus fortement sur la note du SI qu’un actif peu critique. La formule traduit l’idée de chaîne de résilience : le maillon faible doit compter.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _FormulaStepCard(
                title: '5 · Lecture dans OpenIRN',
                icon: Icons.insights_outlined,
                children: [
                  Text(
                    'Dans une campagne créée depuis un SI, le cartouche “Score IRN” affiche la maturité consolidée du SI. Les boutons d’actifs permettent de saisir séparément la grille IRN de chaque actif.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Les critères non renseignés ne participent pas encore au score. La complétude reste donc indispensable pour interpréter correctement la note.',
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
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(label: Text('N.C. — exclu du score')),
        Chip(label: Text('Non résilient — 10/100')),
        Chip(label: Text('Intention — 25/100')),
        Chip(label: Text('Moyen — 50/100')),
        Chip(label: Text('Résultat — 95/100')),
      ],
    );
  }
}
