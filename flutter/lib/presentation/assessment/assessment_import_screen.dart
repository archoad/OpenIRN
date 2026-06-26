import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/files/local_json_file_service.dart';
import '../../data/repositories/local_activity_repository.dart';
import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/assessment_import_service.dart';
import '../common/openirn_app_bar.dart';

class AssessmentImportScreen extends StatefulWidget {
  final IrnReferential referential;

  const AssessmentImportScreen({required this.referential, super.key});

  @override
  State<AssessmentImportScreen> createState() => _AssessmentImportScreenState();
}

class _AssessmentImportScreenState extends State<AssessmentImportScreen> {
  final _controller = TextEditingController();
  final _importService = const AssessmentImportService();
  final _campaignRepository = const LocalCampaignRepository();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _activityRepository = const LocalActivityRepository();
  final _fileService = const LocalJsonFileService();

  bool _isImporting = false;
  bool _isLoadingFile = false;
  String? _errorMessage;
  AssessmentImportResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFromFile() async {
    if (_isLoadingFile || _isImporting) {
      return;
    }

    setState(() {
      _isLoadingFile = true;
      _errorMessage = null;
      _result = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ouverture du dialogue de sélection…')),
    );

    try {
      final file = await _fileService.pickJson();
      if (!mounted) {
        return;
      }
      if (file == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ouverture de fichier annulée.')),
        );
        return;
      }
      setState(() {
        _controller.text = file.content;
        _errorMessage = null;
        _result = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fichier chargé : ${file.name}')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Lecture du fichier impossible : $error';
        _result = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lecture du fichier impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFile = false;
        });
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) {
      return;
    }
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le presse-papiers ne contient pas de texte JSON.'),
        ),
      );
      return;
    }
    setState(() {
      _controller.text = text;
      _errorMessage = null;
      _result = null;
    });
  }

  Future<void> _importJson() async {
    final rawJson = _controller.text;
    if (rawJson.trim().isEmpty) {
      setState(() {
        _errorMessage =
            'Ouvre un fichier .json ou colle d’abord un export JSON OpenIRN.';
        _result = null;
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = _importService.importFromJson(
        rawJson: rawJson,
        referential: widget.referential,
      );
      final campaigns = await _campaignRepository.loadCampaigns(
        referentialId: widget.referential.id,
      );
      await _campaignRepository.saveCampaigns(
        referentialId: widget.referential.id,
        campaigns: <LocalCampaign>[result.campaign, ...campaigns],
      );
      await _assessmentRepository.saveCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: result.campaign.id,
        answers: result.criterionAnswers,
      );
      await _activityRepository.saveEvents(
        referentialId: widget.referential.id,
        campaignId: result.campaign.id,
        events: result.activityEvents,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isImporting = false;
        _result = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campagne importée sur ce terminal.')),
      );
    } on AssessmentImportException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isImporting = false;
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isImporting = false;
        _errorMessage = 'Import impossible : $error';
      });
    }
  }

  void _returnToCampaigns() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OpenIrnAppBar(
        title: 'Importer un JSON OpenIRN',
        actions: [
          OpenIrnAppBarAction(
            id: 'open_file',
            label: _isLoadingFile ? 'Ouverture…' : 'Ouvrir fichier',
            icon: Icons.folder_open_outlined,
            enabled: !_isImporting && !_isLoadingFile,
            onSelected: _loadFromFile,
          ),
          OpenIrnAppBarAction(
            id: 'paste',
            label: 'Coller',
            icon: Icons.content_paste_outlined,
            enabled: !_isImporting,
            onSelected: _pasteFromClipboard,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ImportIntroCard(referential: widget.referential),
              const SizedBox(height: 12),
              if (_errorMessage != null) ...[
                _ImportErrorCard(message: _errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_result != null) ...[
                _ImportSuccessCard(
                  result: _result!,
                  onReturn: _returnToCampaigns,
                ),
                const SizedBox(height: 12),
              ],
              _JsonInputCard(
                controller: _controller,
                isImporting: _isImporting,
                isLoadingFile: _isLoadingFile,
                onOpenFile: _loadFromFile,
                onPaste: _pasteFromClipboard,
                onImport: _importJson,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportIntroCard extends StatelessWidget {
  final IrnReferential referential;

  const _ImportIntroCard({required this.referential});

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
                const Icon(Icons.upload_file_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Import JSON local',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Ouvre un fichier .json exporté depuis OpenIRN ou colle son contenu. L’import vérifie que le référentiel cible correspond au référentiel actuellement chargé, puis crée une nouvelle campagne avec ses réponses, ses justifications et son journal d’activité.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Référentiel actif : ${referential.id}')),
                Chip(label: Text('Version : ${referential.version}')),
                if ((referential.checksumSha256 ?? '').isNotEmpty)
                  Chip(label: Text('SHA-256 : ${referential.checksumSha256}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JsonInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isImporting;
  final bool isLoadingFile;
  final VoidCallback onOpenFile;
  final VoidCallback onPaste;
  final VoidCallback onImport;

  const _JsonInputCard({
    required this.controller,
    required this.isImporting,
    required this.isLoadingFile,
    required this.onOpenFile,
    required this.onPaste,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contenu JSON',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 12,
              maxLines: 22,
              enabled: !isImporting,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    '{\n  "schemaVersion": 5,\n  "type": "openirn.localAssessmentExport"\n}',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: (isImporting || isLoadingFile) ? null : onOpenFile,
                  icon: isLoadingFile
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(isLoadingFile ? 'Ouverture…' : 'Ouvrir .json'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: isImporting ? null : onPaste,
                  icon: const Icon(Icons.content_paste_outlined),
                  label: const Text('Coller'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: isImporting ? null : onImport,
                  icon: isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(isImporting ? 'Import en cours…' : 'Importer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportSuccessCard extends StatelessWidget {
  final AssessmentImportResult result;
  final VoidCallback onReturn;

  const _ImportSuccessCard({required this.result, required this.onReturn});

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
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Import terminé',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onReturn,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Retour aux campagnes'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Campagne créée : ${result.campaign.name}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Réponses cotées : ${result.answeredCount}')),
                Chip(
                  label: Text('Justifications : ${result.justificationCount}'),
                ),
                Chip(
                  label: Text(
                    'Évènements journal : ${result.activityEvents.length}',
                  ),
                ),
                Chip(label: Text('Avertissements : ${result.warnings.length}')),
              ],
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Avertissements',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final warning in result.warnings.take(8)) Text('• $warning'),
              if (result.warnings.length > 8)
                Text(
                  '• … ${result.warnings.length - 8} autre(s) avertissement(s)',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportErrorCard extends StatelessWidget {
  final String message;

  const _ImportErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
