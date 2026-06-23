import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/models/irn_referential.dart';

class AboutScreen extends StatefulWidget {
  final IrnReferential referential;

  const AboutScreen({
    required this.referential,
    super.key,
  });

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('À propos'),
      ),
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
              const SizedBox(height: 12),
              _LicenseCard(referential: widget.referential),
              if (widget.referential.importWarnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ImportWarningsCard(warnings: widget.referential.importWarnings),
              ],
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
                        'Application open source d’exploration et d’évaluation locale de l’Indice de Résilience Numérique.',
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
                    Chip(label: Text('${referential.pillars.length} piliers')),
                    Chip(label: Text('${referential.criteria.length} critères')),
                    Chip(label: Text('Référentiel ${referential.version}')),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'OpenIRN distingue clairement le code de l’application, le référentiel officiel aDRI importé, et les campagnes locales créées par l’utilisateur.',
            ),
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
              'Référentiel officiel utilisé',
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
            if (referential.source.projectPath.isNotEmpty)
              _InfoRow(
                label: 'Projet source',
                value: referential.source.projectPath,
              ),
            if (referential.source.defaultBranch.isNotEmpty)
              _InfoRow(
                label: 'Branche',
                value: referential.source.defaultBranch,
              ),
            if (referential.source.filePath.isNotEmpty)
              _InfoRow(
                label: 'Fichier importé',
                value: referential.source.filePath,
              ),
            if (referential.source.commitSha != null &&
                referential.source.commitSha!.isNotEmpty)
              _InfoRow(
                label: 'Commit',
                value: referential.source.commitSha!,
                selectable: true,
              ),
            if (referential.checksumSha256 != null &&
                referential.checksumSha256!.isNotEmpty)
              _InfoRow(
                label: 'SHA-256',
                value: referential.checksumSha256!,
                selectable: true,
              ),
            if (referential.importedAt != null)
              _InfoRow(
                label: 'Importé le',
                value: referential.importedAt!.toLocal().toString(),
              ),
          ],
        ),
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  final IrnReferential referential;

  const _LicenseCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Licence et attribution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Licence du référentiel',
              value: referential.license,
            ),
            const SizedBox(height: 8),
            const Text(
              'Le référentiel IRN importé est attribué à l’aDRI / Digital Resilience Initiative. '
              'OpenIRN conserve la source, la version et le checksum du fichier importé afin de faciliter la traçabilité.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Les campagnes, réponses, justifications, scores et journaux produits dans OpenIRN sont des données locales distinctes du référentiel officiel.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportWarningsCard extends StatelessWidget {
  final List<String> warnings;

  const _ImportWarningsCard({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Avertissements d’import',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(warning)),
                  ],
                ),
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
