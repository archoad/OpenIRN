import 'package:flutter/material.dart';

import '../../domain/models/irn_referential.dart';
import '../../domain/repositories/irn_referential_repository.dart';
import '../../domain/services/referential_catalog_service.dart';
import '../about/about_screen.dart';
import '../campaigns/campaign_list_screen.dart';
import 'criterion_detail_screen.dart';

class ReferentialOverviewScreen extends StatefulWidget {
  final IrnReferentialRepository repository;

  const ReferentialOverviewScreen({
    required this.repository,
    super.key,
  });

  @override
  State<ReferentialOverviewScreen> createState() =>
      _ReferentialOverviewScreenState();
}

class _ReferentialOverviewScreenState extends State<ReferentialOverviewScreen> {
  final _service = const ReferentialCatalogService();
  final _searchController = TextEditingController();
  late final Future<IrnReferential> _referentialFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _referentialFuture = widget.repository.getActiveReferential();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenIRN — Référentiel officiel'),
        actions: [
          FutureBuilder<IrnReferential>(
            future: _referentialFuture,
            builder: (context, snapshot) {
              final referential = snapshot.data;
              return IconButton(
                tooltip: 'À propos / Licence',
                onPressed: referential == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AboutScreen(referential: referential),
                          ),
                        ),
                icon: const Icon(Icons.info_outline),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<IrnReferential>(
        future: _referentialFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error.toString());
          }
          final referential = snapshot.data;
          if (referential == null) {
            return const _ErrorState(error: 'Référentiel absent.');
          }

          return _ReferentialContent(
            referential: referential,
            service: _service,
            query: _query,
            searchController: _searchController,
          );
        },
      ),
    );
  }
}

class _ReferentialContent extends StatelessWidget {
  final IrnReferential referential;
  final ReferentialCatalogService service;
  final TextEditingController searchController;
  final String query;

  const _ReferentialContent({
    required this.referential,
    required this.service,
    required this.searchController,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final scopes = service.criteriaCountByScope(referential);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(referential: referential),
            const SizedBox(height: 12),
            _ScopeChips(scopes: scopes),
            const SizedBox(height: 12),
            _AssessmentLaunchCard(referential: referential),
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher un critère',
                hintText: 'Ex. RES-6, gouvernance, actif, portabilité...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        onPressed: searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            for (final pillar in referential.pillars)
              _PillarExpansionTile(
                pillar: pillar,
                criteria: service.criteriaForPillar(referential, pillar.id,
                    query: query),
                initiallyExpanded: query.trim().isNotEmpty,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final IrnReferential referential;

  const _HeaderCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('aDRI IRN ${referential.version}',
                style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
                '${referential.pillars.length} piliers · ${referential.criteria.length} critères'),
            const SizedBox(height: 8),
            SelectableText('Source : ${referential.sourceUrl}'),
            const SizedBox(height: 4),
            Text('Licence : ${referential.license}'),
            if (referential.source.filePath.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Fichier : ${referential.source.filePath}'),
            ],
            if (referential.checksumSha256 != null &&
                referential.checksumSha256!.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText('SHA-256 : ${referential.checksumSha256}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScopeChips extends StatelessWidget {
  final Map<CriterionScope, int> scopes;

  const _ScopeChips({required this.scopes});

  @override
  Widget build(BuildContext context) {
    final entries = scopes.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          Chip(label: Text('${entry.key.label} : ${entry.value}')),
      ],
    );
  }
}

class _AssessmentLaunchCard extends StatelessWidget {
  final IrnReferential referential;

  const _AssessmentLaunchCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.fact_check_outlined, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Évaluation R / NR locale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Créer ou ouvrir une campagne locale pour tester le futur moteur de notation officiel.',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CampaignListScreen(referential: referential),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Démarrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarExpansionTile extends StatelessWidget {
  final IrnPillar pillar;
  final List<IrnCriterion> criteria;
  final bool initiallyExpanded;

  const _PillarExpansionTile({
    required this.pillar,
    required this.criteria,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded && criteria.isNotEmpty,
        title: Text('${pillar.code} — ${pillar.label}'),
        subtitle:
            Text('${criteria.length} critère${criteria.length > 1 ? 's' : ''}'),
        children: [
          if (criteria.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(
                  'Aucun critère ne correspond à la recherche dans ce pilier.'),
            ),
          for (final criterion in criteria)
            ListTile(
              leading: CircleAvatar(
                child: Text(criterion.code.split('.').last),
              ),
              title: Text('${criterion.code} — ${criterion.label}'),
              subtitle: Text(
                  'Portée : ${criterion.scope.label} · Réponse : ${criterion.answerMode}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CriterionDetailScreen(
                    pillar: pillar,
                    criterion: criterion,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger le référentiel',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
              'Vérifie que le bundle a été généré dans flutter/assets/referentials/.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
