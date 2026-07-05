import 'package:flutter/material.dart';

import '../../domain/models/irn_referential.dart';
import '../../l10n/openirn_localizations.dart';
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
                            label: Text(
                              context.tr(
                                'criterion.scope.value',
                                values: {
                                  'scope': context.trText(
                                    criterion.scope.label,
                                  ),
                                },
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              context.tr(
                                'criterion.answer.value',
                                values: {'answer': criterion.answerMode},
                              ),
                            ),
                          ),
                          if (!criterion.active)
                            Chip(label: Text(context.tr('common.inactive'))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _SectionCard(
                title: context.tr('referential.detail.objective_title'),
                content: criterion.description,
                emptyMessage: context.tr(
                  'referential.detail.empty_description',
                ),
              ),
              _SectionCard(
                title: context.tr('referential.detail.recommendations_title'),
                content: criterion.recommendations,
                emptyMessage: context.tr(
                  'referential.detail.empty_recommendations',
                ),
              ),
              _SectionCard(
                title: context.tr('referential.detail.regulatory_title'),
                content: criterion.regulatoryReferences,
                emptyMessage: context.tr('referential.detail.empty_regulatory'),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('referential.detail.traceability'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        context.tr(
                          'referential.detail.source_code',
                          values: {'code': criterion.sourceCode},
                        ),
                      ),
                      if (criterion.sourceScope.isNotEmpty)
                        SelectableText(
                          context.tr(
                            'referential.detail.source_scope',
                            values: {'scope': criterion.sourceScope},
                          ),
                        ),
                      if (criterion.source.sheet.isNotEmpty)
                        SelectableText(
                          context.tr(
                            'referential.detail.sheet',
                            values: {'sheet': criterion.source.sheet},
                          ),
                        ),
                      if (criterion.source.row != null)
                        SelectableText(
                          context.tr(
                            'referential.detail.row',
                            values: {'row': criterion.source.row},
                          ),
                        ),
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
            Text(
              context.trText(title),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              normalized.isEmpty ? context.trText(emptyMessage) : normalized,
            ),
          ],
        ),
      ),
    );
  }
}
