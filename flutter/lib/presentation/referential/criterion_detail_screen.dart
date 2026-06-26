import 'package:flutter/material.dart';

import '../../domain/models/irn_referential.dart';
import '../common/openirn_app_bar.dart';

class CriterionDetailScreen extends StatelessWidget {
  final IrnPillar pillar;
  final IrnCriterion criterion;

  const CriterionDetailScreen({
    required this.pillar,
    required this.criterion,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(title: criterion.code),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${criterion.code} — ${criterion.label}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text(pillar.label)),
                          Chip(
                            label: Text('Portée : ${criterion.scope.label}'),
                          ),
                          Chip(
                            label: Text('Réponse : ${criterion.answerMode}'),
                          ),
                          if (!criterion.active)
                            const Chip(label: Text('Inactif')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _SectionCard(
                title: 'Objectif / description',
                content: criterion.description,
                emptyMessage: 'Aucune description renseignée.',
              ),
              _SectionCard(
                title: 'Recommandations',
                content: criterion.recommendations,
                emptyMessage: 'Aucune recommandation renseignée.',
              ),
              _SectionCard(
                title: 'Références réglementaires',
                content: criterion.regulatoryReferences,
                emptyMessage: 'Aucune référence réglementaire renseignée.',
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Traçabilité',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText('Code source : ${criterion.sourceCode}'),
                      if (criterion.sourceScope.isNotEmpty)
                        SelectableText(
                          'Portée source : ${criterion.sourceScope}',
                        ),
                      if (criterion.source.sheet.isNotEmpty)
                        SelectableText('Onglet : ${criterion.source.sheet}'),
                      if (criterion.source.row != null)
                        SelectableText('Ligne : ${criterion.source.row}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String content;
  final String emptyMessage;

  const _SectionCard({
    required this.title,
    required this.content,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = content.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(normalized.isEmpty ? emptyMessage : normalized),
          ],
        ),
      ),
    );
  }
}
