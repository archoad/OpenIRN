import 'package:flutter/material.dart';

import '../../data/repositories/local_assessment_repository.dart';
import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/assessment_quality_service.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../../domain/services/access_policy_service.dart';
import '../assessment/assessment_screen.dart';
import '../common/openirn_app_bar.dart';

class CampaignListScreen extends StatefulWidget {
  final IrnReferential referential;
  final AppUser activeUser;

  const CampaignListScreen({
    required this.referential,
    required this.activeUser,
    super.key,
  });

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  final _campaignRepository = const LocalCampaignRepository();
  final _assessmentRepository = const LocalAssessmentRepository();
  final _scoringService = const OfficialRnrScoringService();
  final _qualityService = const AssessmentQualityService();
  final _appSyncCoordinator = AppSyncCoordinator.instance;
  final _accessPolicy = const AccessPolicyService();

  late Future<_CampaignListState> _campaignsFuture;
  int _lastAppliedSyncSerial = 0;

  @override
  void initState() {
    super.initState();
    _campaignsFuture = _loadCampaigns();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
  }

  @override
  void dispose() {
    _appSyncCoordinator.removeListener(_handleBackgroundSyncUpdate);
    super.dispose();
  }

  void _handleBackgroundSyncUpdate() {
    final serial = _appSyncCoordinator.changeSerial;
    if (!mounted || serial == _lastAppliedSyncSerial) {
      return;
    }
    _lastAppliedSyncSerial = serial;
    _refresh();
  }

  Future<_CampaignListState> _loadCampaigns() async {
    final campaigns = await _campaignRepository.loadCampaigns(
      referentialId: widget.referential.id,
    );

    final enriched = <_CampaignWithSummary>[];
    for (final campaign in campaigns) {
      final criterionAnswers = await _assessmentRepository.loadCriterionAnswers(
        referentialId: widget.referential.id,
        campaignId: campaign.id,
      );
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      final summary = _scoringService.computeSummary(
        widget.referential,
        answers,
      );
      final qualityReport = _qualityService.buildReport(
        referential: widget.referential,
        criterionAnswers: criterionAnswers,
        campaign: campaign,
      );
      enriched.add(
        _CampaignWithSummary(
          campaign: campaign,
          criterionAnswers: criterionAnswers,
          answers: answers,
          summary: summary,
          qualityReport: qualityReport,
        ),
      );
    }
    return _CampaignListState(campaigns: enriched);
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _campaignsFuture = _loadCampaigns();
    });
    await _campaignsFuture;
  }

  void _showForbidden(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCampaign(LocalCampaign campaign) async {
    if (!_accessPolicy.canReadCampaign(widget.activeUser)) {
      _showForbidden('Votre profil ne permet pas d’ouvrir les campagnes.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentScreen(
          referential: widget.referential,
          campaign: campaign,
          activeUser: widget.activeUser,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OpenIrnAppBar(title: 'Campagnes'),
      body: FutureBuilder<_CampaignListState>(
        future: _campaignsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final state = snapshot.data;
          final campaigns = state?.campaigns ?? <_CampaignWithSummary>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _HeaderCard(referential: widget.referential),
                  const SizedBox(height: 12),
                  if (campaigns.isEmpty)
                    const _NoCampaignState()
                  else
                    for (final campaign in campaigns)
                      _CampaignCard(
                        entry: campaign,
                        onOpen: () => _openCampaign(campaign.campaign),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CampaignListState {
  final List<_CampaignWithSummary> campaigns;

  const _CampaignListState({required this.campaigns});
}

class _CampaignWithSummary {
  final LocalCampaign campaign;
  final Map<String, CriterionAnswer> criterionAnswers;
  final Map<String, IrnAnswer> answers;
  final IrnScoreSummary summary;
  final AssessmentQualityReport qualityReport;

  const _CampaignWithSummary({
    required this.campaign,
    required this.criterionAnswers,
    required this.answers,
    required this.summary,
    required this.qualityReport,
  });
}

class _HeaderCard extends StatelessWidget {
  final IrnReferential referential;

  const _HeaderCard({required this.referential});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.folder_copy_outlined, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Campagnes OpenIRN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Référentiel : ${referential.id} · ${referential.version}',
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final _CampaignWithSummary entry;
  final VoidCallback onOpen;

  const _CampaignCard({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final campaign = entry.campaign;
    final summary = entry.summary;
    final qualityReport = entry.qualityReport;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (campaign.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(campaign.description),
                      ],
                      if (campaign.information.systemName
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'SI : ${campaign.information.systemName}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (campaign
                              .information
                              .projectDirectorFullName
                              .isNotEmpty ||
                          campaign.information.projectDirectorEmail
                              .trim()
                              .isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Directeur projet : ${_projectDirectorLabel(campaign.information)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  summary.formattedOpenIrnRnrScore,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: summary.openIrnRnrScore == null
                  ? 0
                  : summary.openIrnRnrScore! / 100,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(campaign.status.label),
                ),
                Chip(
                  label: Text(
                    'Cotés : ${summary.answeredCriteria}/${summary.totalCriteria}',
                  ),
                ),
                Chip(label: Text('R : ${summary.resilientCriteria}')),
                Chip(label: Text('NR : ${summary.nonResilientCriteria}')),
                Chip(
                  label: Text(
                    'Complétude : ${(summary.completionRate * 100).toStringAsFixed(0)} %',
                  ),
                ),
                Chip(label: Text('Maj : ${_formatDate(campaign.updatedAt)}')),
                Chip(
                  avatar: Icon(
                    qualityReport.isCampaignInformationComplete
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                  ),
                  label: Text(
                    qualityReport.isCampaignInformationComplete
                        ? 'Infos campagne OK'
                        : 'Infos manquantes : ${qualityReport.missingCampaignInformationCount}',
                  ),
                ),
                if (campaign.isReadOnly)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 18),
                    label: Text('Lecture seule'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              campaign.status.helperText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.login_outlined),
                label: const Text('Ouvrir'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _projectDirectorLabel(CampaignInformation information) {
    final name = information.projectDirectorFullName;
    final email = information.projectDirectorEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name <$email>';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return 'non renseigné';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _NoCampaignState extends StatelessWidget {
  const _NoCampaignState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.folder_off_outlined, size: 44),
            SizedBox(height: 12),
            Text('Aucune campagne disponible.'),
            SizedBox(height: 6),
            Text(
              'Utilise le menu ⋮ puis “Gérer les campagnes” pour créer une campagne.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text('Impossible de charger les campagnes : $error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
