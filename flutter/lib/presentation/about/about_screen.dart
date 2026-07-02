import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/models/irn_referential.dart';
import '../common/openirn_app_bar.dart';

class AboutScreen extends StatefulWidget {
  final IrnReferential referential;

  const AboutScreen({required this.referential, super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'À propos'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ApplicationCard(
                referential: widget.referential,
                packageInfoFuture: _packageInfoFuture,
              ),
              const SizedBox(height: 12),
              _ReferentialCard(referential: widget.referential),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final IrnReferential referential;
  final Future<PackageInfo> packageInfoFuture;

  const _ApplicationCard({
    required this.referential,
    required this.packageInfoFuture,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OpenIRN', style: textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      const Text(
                        'Application open source d’exploration et d’évaluation de l’Indice de Résilience Numérique.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<PackageInfo>(
              future: packageInfoFuture,
              builder: (context, snapshot) {
                final info = snapshot.data;
                final versionLabel = info == null
                    ? 'Version en cours de chargement'
                    : _formatPackageVersion(info);

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('OpenIRN $versionLabel')),
                    Chip(label: Text('Référentiel ${referential.version}')),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Copyright © Michel Dubois 2026'),
          ],
        ),
      ),
    );
  }
}

class _ReferentialCard extends StatelessWidget {
  final IrnReferential referential;

  const _ReferentialCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Référentiel utilisé',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Identifiant', value: referential.id),
            _InfoRow(label: 'Version', value: referential.version),
            _InfoRow(
              label: 'Source',
              value: referential.sourceUrl,
              selectable: true,
            ),
            if (referential.source.filePath.isNotEmpty)
              _InfoRow(
                label: 'Fichier importé',
                value: referential.source.filePath,
              ),
            if (referential.importedAt != null)
              _InfoRow(
                label: 'Importé le',
                value: referential.importedAt!.toLocal().toString(),
              ),
            _InfoRow(
              label: 'Licence du référentiel',
              value: referential.license,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;

  const _InfoRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 2),
          if (selectable) SelectableText(value) else Text(value),
        ],
      ),
    );
  }
}

String _formatPackageVersion(PackageInfo info) {
  final version = info.version.trim();
  final buildNumber = info.buildNumber.trim();

  if (buildNumber.isEmpty) {
    return version;
  }

  return '$version+$buildNumber';
}
