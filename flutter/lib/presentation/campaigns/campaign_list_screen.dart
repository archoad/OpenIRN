import 'package:flutter/material.dart';

import '../../data/repositories/local_campaign_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/irn_assessment.dart';
import '../../domain/models/irn_referential.dart';
import '../../domain/models/local_campaign.dart';
import '../../domain/services/app_sync_coordinator.dart';
import '../../domain/services/assessment_quality_service.dart';
import '../../domain/services/official_rnr_scoring_service.dart';
import '../../domain/services/access_policy_service.dart';
import '../../l10n/openirn_localizations.dart';
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
  final _scoringService = const OfficialRnrScoringService();
  final _qualityService = const AssessmentQualityService();
  final _appSyncCoordinator = AppSyncCoordinator.instance;
  final _accessPolicy = const AccessPolicyService();

  _CampaignListState? _campaignState;
  Object? _loadError;
  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  Future<void>? _refreshInFlight;
  int _lastAppliedSyncSerial = 0;

  @override
  void initState() {
    super.initState();
    _lastAppliedSyncSerial = _appSyncCoordinator.changeSerial;
    _appSyncCoordinator.addListener(_handleBackgroundSyncUpdate);
    _refresh();
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
    final campaignData = await _campaignRepository.loadCampaignData(
      referentialId: widget.referential.id,
    );

    final enriched = <_CampaignWithSummary>[];
    for (final data in campaignData) {
      final campaign = data.campaign;
      final criterionAnswers = data.criterionAnswers;
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      final maturitySummary = campaign.information.isAssetScoped
          ? _scoringService.computeSystemMaturity(
              widget.referential,
              campaign,
              criterionAnswers,
            )
          : null;
      final summary =
          maturitySummary?.aggregateSummary ??
          _computeCampaignSummary(campaign, criterionAnswers);
      final qualityReport = _buildQualityReport(campaign, criterionAnswers);
      enriched.add(
        _CampaignWithSummary(
          campaign: campaign,
          criterionAnswers: criterionAnswers,
          answers: answers,
          summary: summary,
          maturitySummary: maturitySummary,
          qualityReport: qualityReport,
        ),
      );
    }
    return _CampaignListState(campaigns: enriched);
  }

  IrnScoreSummary _computeCampaignSummary(
    LocalCampaign campaign,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    if (!campaign.information.isAssetScoped) {
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      return _scoringService.computeSummary(widget.referential, answers);
    }

    final criteria = widget.referential.criteria
        .where((criterion) => criterion.active)
        .toList(growable: false);
    var total = 0;
    var notConcerned = 0;
    var nonResilient = 0;
    var intention = 0;
    var medium = 0;
    var result = 0;
    var notAnswered = 0;
    var scorePointsTotal = 0;

    for (final asset in campaign.information.assets) {
      for (final criterion in criteria) {
        total += 1;
        final key = 'asset:${asset.id}:criterion:${criterion.id}';
        final answer = criterionAnswers[key]?.answer ?? IrnAnswer.notAnswered;
        switch (answer) {
          case IrnAnswer.notConcerned:
            notConcerned += 1;
          case IrnAnswer.nonResilient:
            nonResilient += 1;
            scorePointsTotal += answer.scoreValue ?? 0;
          case IrnAnswer.intention:
            intention += 1;
            scorePointsTotal += answer.scoreValue ?? 0;
          case IrnAnswer.medium:
            medium += 1;
            scorePointsTotal += answer.scoreValue ?? 0;
          case IrnAnswer.result:
            result += 1;
            scorePointsTotal += answer.scoreValue ?? 0;
          case IrnAnswer.notAnswered:
            notAnswered += 1;
        }
      }
    }

    return IrnScoreSummary(
      totalCriteria: total,
      answeredCriteria:
          notConcerned + nonResilient + intention + medium + result,
      notConcernedCriteria: notConcerned,
      nonResilientCriteria: nonResilient,
      intentionCriteria: intention,
      mediumCriteria: medium,
      resultCriteria: result,
      notAnsweredCriteria: notAnswered,
      scorePointsTotal: scorePointsTotal,
    );
  }

  /// Builds the quality report for [campaign], aggregating across every
  /// scoped asset when [campaign] is asset-scoped. `AssessmentQualityService`
  /// expects a flat `criterionId -> answer` map, but asset-scoped campaigns
  /// store answers under composite `asset:<assetId>:criterion:<criterionId>`
  /// keys — so each asset's slice must be flattened and reported on
  /// separately, then merged, or every answer would be reported as missing.
  AssessmentQualityReport _buildQualityReport(
    LocalCampaign campaign,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    if (!campaign.information.isAssetScoped) {
      return _qualityService.buildReport(
        referential: widget.referential,
        criterionAnswers: criterionAnswers,
        campaign: campaign,
      );
    }

    final assets = campaign.information.assets;
    if (assets.isEmpty) {
      return _qualityService.buildReport(
        referential: widget.referential,
        criterionAnswers: const <String, CriterionAnswer>{},
        campaign: campaign,
      );
    }

    final perAssetReports = [
      for (final asset in assets)
        _qualityService.buildReport(
          referential: widget.referential,
          criterionAnswers: _flattenAssetAnswers(asset.id, criterionAnswers),
          campaign: campaign,
        ),
    ];
    return _mergeQualityReports(perAssetReports);
  }

  Map<String, CriterionAnswer> _flattenAssetAnswers(
    String assetId,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    final prefix = 'asset:$assetId:criterion:';
    final flattened = <String, CriterionAnswer>{};
    for (final entry in criterionAnswers.entries) {
      if (!entry.key.startsWith(prefix)) {
        continue;
      }
      final criterionId = entry.key.substring(prefix.length);
      if (criterionId.isEmpty) {
        continue;
      }
      flattened[criterionId] = CriterionAnswer(
        criterionId: criterionId,
        answer: entry.value.answer,
        justification: entry.value.justification,
      );
    }
    return flattened;
  }

  AssessmentQualityReport _mergeQualityReports(
    List<AssessmentQualityReport> reports,
  ) {
    var totalCriteria = 0;
    var answeredCriteria = 0;
    var justifiedCriteria = 0;
    final missingAnswers = <IrnCriterion>[];
    final missingJustifications = <AssessmentQualityIssue>[];
    for (final report in reports) {
      totalCriteria += report.totalCriteria;
      answeredCriteria += report.answeredCriteria;
      justifiedCriteria += report.justifiedCriteria;
      missingAnswers.addAll(report.missingAnswers);
      missingJustifications.addAll(report.missingJustifications);
    }
    return AssessmentQualityReport(
      totalCriteria: totalCriteria,
      answeredCriteria: answeredCriteria,
      justifiedCriteria: justifiedCriteria,
      missingAnswers: List.unmodifiable(missingAnswers),
      missingJustifications: List.unmodifiable(missingJustifications),
      missingCampaignInformation: reports.first.missingCampaignInformation,
    );
  }

  Future<void> _refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> refresh;
    refresh = _performRefresh().whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<void> _performRefresh() async {
    if (!mounted) {
      return;
    }

    final hasVisibleData = _campaignState != null;
    setState(() {
      _loadError = null;
      _isInitialLoading = !hasVisibleData;
      _isRefreshing = hasVisibleData;
    });

    try {
      final state = await _loadCampaigns();
      if (!mounted) {
        return;
      }
      setState(() {
        _campaignState = state;
        _loadError = null;
        _isInitialLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _isInitialLoading = false;
        _isRefreshing = false;
      });
    }
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
      _showForbidden(
        context.tr(
          'screen.campaign.list.forbidden.open',
          fallback: 'Votre profil ne permet pas d’ouvrir les campagnes.',
        ),
      );
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
      body: Builder(
        builder: (context) {
          final state = _campaignState;
          if (state == null) {
            if (_isInitialLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _ErrorState(error: _loadError.toString(), onRetry: _refresh);
          }

          return Column(
            children: [
              if (_isRefreshing) const LinearProgressIndicator(),
              if (_loadError != null)
                MaterialBanner(
                  content: Text(
                    context.tr(
                      'screen.campaign.list.error.load',
                      fallback: 'Impossible de charger les campagnes : {error}',
                      values: {'error': _loadError.toString()},
                    ),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        context.tr('action.retry', fallback: 'Réessayer'),
                      ),
                    ),
                  ],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _HeaderCard(referential: widget.referential),
                        const SizedBox(height: 12),
                        if (state.campaigns.isEmpty)
                          const _NoCampaignState()
                        else
                          for (final campaign in state.campaigns)
                            _CampaignCard(
                              entry: campaign,
                              onOpen: () => _openCampaign(campaign.campaign),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
  final IrnSystemMaturitySummary? maturitySummary;
  final AssessmentQualityReport qualityReport;

  const _CampaignWithSummary({
    required this.campaign,
    required this.criterionAnswers,
    required this.answers,
    required this.summary,
    required this.maturitySummary,
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
                    context.tr(
                      'screen.campaign.list.header.title',
                      fallback: 'Campagnes OpenIRN',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'screen.campaign.list.header.referential',
                      fallback: 'Référentiel : {id} · {version}',
                      values: {
                        'id': referential.id,
                        'version': referential.version,
                      },
                    ),
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
    final maturitySummary = entry.maturitySummary;
    final displayedScore =
        maturitySummary?.maturityScore ?? summary.openIrnRnrScore;
    final displayedScoreLabel =
        maturitySummary?.formattedMaturityScore ??
        summary.formattedOpenIrnRnrScore;
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
                          context.tr(
                            'screen.campaign.list.card.system',
                            fallback: 'SI : {system}',
                            values: {'system': campaign.information.systemName},
                          ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (campaign.information.isAssetScoped) ...[
                        const SizedBox(height: 2),
                        Text(
                          context.tr(
                            'screen.campaign.list.card.asset_scoring',
                            fallback: 'Notation par actif : {count} actif(s)',
                            values: {
                              'count': campaign.information.assets.length,
                            },
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
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
                          context.tr(
                            'screen.campaign.list.card.project_director',
                            fallback: 'Directeur du SI : {director}',
                            values: {
                              'director': _projectDirectorLabel(
                                context,
                                campaign.information,
                              ),
                            },
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  displayedScoreLabel,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: displayedScore == null ? 0 : displayedScore / 100,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(_statusLabel(context, campaign.status)),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.answered',
                      fallback: 'Renseignés : {answered}/{total}',
                      values: {
                        'answered': summary.answeredCriteria,
                        'total': summary.totalCriteria,
                      },
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.not_concerned',
                      fallback: 'N.C. : {count}',
                      values: {'count': summary.notConcernedCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.non_resilient',
                      fallback: 'NR : {count}',
                      values: {'count': summary.nonResilientCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.intention',
                      fallback: 'Intention : {count}',
                      values: {'count': summary.intentionCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.medium',
                      fallback: 'Moyen : {count}',
                      values: {'count': summary.mediumCriteria},
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.result',
                      fallback: 'Résultat : {count}',
                      values: {'count': summary.resultCriteria},
                    ),
                  ),
                ),
                if (maturitySummary != null) ...[
                  Chip(
                    label: Text(
                      context.tr(
                        'screen.campaign.list.chip.scored_assets',
                        fallback: 'Actifs notés : {scored}/{total}',
                        values: {
                          'scored': maturitySummary.scoredAssetCount,
                          'total': maturitySummary.totalAssetCount,
                        },
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      context.tr(
                        'screen.campaign.list.chip.criticality_weight',
                        fallback: 'Poids criticité : {weight}',
                        values: {'weight': maturitySummary.maturityWeightTotal},
                      ),
                    ),
                  ),
                ],
                Chip(
                  label: Text(
                    context.tr(
                      'screen.campaign.list.chip.completion',
                      fallback: 'Complétude : {rate} %',
                      values: {
                        'rate': (summary.completionRate * 100).toStringAsFixed(
                          0,
                        ),
                      },
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    context.tr(
                      'common.updated_at_short',
                      fallback: 'Maj : {date}',
                      values: {'date': _formatDate(campaign.updatedAt)},
                    ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    qualityReport.isCampaignInformationComplete
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                  ),
                  label: Text(
                    qualityReport.isCampaignInformationComplete
                        ? context.tr(
                            'screen.campaign.list.chip.info_ok',
                            fallback: 'Infos campagne OK',
                          )
                        : context.tr(
                            'screen.campaign.list.chip.info_missing',
                            fallback: 'Infos manquantes : {count}',
                            values: {
                              'count':
                                  qualityReport.missingCampaignInformationCount,
                            },
                          ),
                  ),
                ),
                if (campaign.isReadOnly)
                  Chip(
                    avatar: const Icon(Icons.lock_outline, size: 18),
                    label: Text(
                      context.tr(
                        'screen.campaign.list.chip.read_only',
                        fallback: 'Lecture seule',
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _statusHelperText(context, campaign.status),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.login_outlined),
                label: Text(context.tr('action.open', fallback: 'Ouvrir')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, LocalCampaignStatus status) {
    switch (status) {
      case LocalCampaignStatus.draft:
        return context.tr('campaign.status.draft', fallback: 'Brouillon');
      case LocalCampaignStatus.readyForReview:
        return context.tr(
          'campaign.status.ready_for_review',
          fallback: 'Prêt pour revue',
        );
      case LocalCampaignStatus.validated:
        return context.tr('campaign.status.validated', fallback: 'Validé');
      case LocalCampaignStatus.archived:
        return context.tr('campaign.status.archived', fallback: 'Archivé');
    }
  }

  String _statusHelperText(BuildContext context, LocalCampaignStatus status) {
    switch (status) {
      case LocalCampaignStatus.draft:
        return context.tr(
          'campaign.status.draft.helper',
          fallback: 'La campagne peut encore être complétée.',
        );
      case LocalCampaignStatus.readyForReview:
        return context.tr(
          'campaign.status.ready_for_review.helper',
          fallback: 'La campagne est complète et peut être relue.',
        );
      case LocalCampaignStatus.validated:
        return context.tr(
          'campaign.status.validated.helper',
          fallback: 'La campagne est validée et passe en lecture seule.',
        );
      case LocalCampaignStatus.archived:
        return context.tr(
          'campaign.status.archived.helper',
          fallback: 'La campagne est archivée et reste consultable.',
        );
    }
  }

  String _projectDirectorLabel(
    BuildContext context,
    CampaignInformation information,
  ) {
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
    return context.tr('common.not_provided', fallback: 'non renseigné');
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.folder_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'screen.campaign.list.empty.title',
                fallback: 'Aucune campagne disponible.',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'screen.campaign.list.empty.subtitle',
                fallback:
                    'Utilise le menu ⋮ puis “Gérer les campagnes” pour créer une campagne.',
              ),
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
            Text(
              context.tr(
                'screen.campaign.list.error.load',
                fallback: 'Impossible de charger les campagnes : {error}',
                values: {'error': error},
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('action.retry', fallback: 'Réessayer')),
            ),
          ],
        ),
      ),
    );
  }
}
