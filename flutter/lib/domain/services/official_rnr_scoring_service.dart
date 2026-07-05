import 'dart:math' as math;

import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';

class OfficialRnrScoringService {
  const OfficialRnrScoringService();

  static const methodMetadata = IrnScoringMethod.openIrnRnr();

  IrnScoreSummary computeSummary(
    IrnReferential referential,
    Map<String, IrnAnswer> answers,
  ) {
    return computeSummaryForCriteria(referential.criteria, answers);
  }

  Map<IrnPillar, IrnScoreSummary> computeSummariesByPillar(
    IrnReferential referential,
    Map<String, IrnAnswer> answers,
  ) {
    return <IrnPillar, IrnScoreSummary>{
      for (final pillar in referential.pillars)
        pillar: computeSummaryForPillar(referential, pillar.id, answers),
    };
  }

  Map<CriterionScope, IrnScoreSummary> computeSummariesByScope(
    IrnReferential referential,
    Map<String, IrnAnswer> answers,
  ) {
    final scopes = <CriterionScope, List<IrnCriterion>>{};
    for (final criterion in referential.criteria) {
      if (!criterion.active) {
        continue;
      }
      scopes
          .putIfAbsent(criterion.scope, () => <IrnCriterion>[])
          .add(criterion);
    }

    final entries = scopes.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return <CriterionScope, IrnScoreSummary>{
      for (final entry in entries)
        entry.key: computeSummaryForCriteria(entry.value, answers),
    };
  }

  IrnScoreSummary computeSummaryForPillar(
    IrnReferential referential,
    String pillarId,
    Map<String, IrnAnswer> answers,
  ) {
    final criteria = referential.criteria
        .where((criterion) => criterion.pillarId == pillarId)
        .toList(growable: false);
    return computeSummaryForCriteria(criteria, answers);
  }

  IrnScoreSummary computeSummaryForCriteria(
    Iterable<IrnCriterion> criteria,
    Map<String, IrnAnswer> answers,
  ) {
    var total = 0;
    var notConcerned = 0;
    var nonResilient = 0;
    var intention = 0;
    var medium = 0;
    var result = 0;
    var notAnswered = 0;
    var scorePointsTotal = 0;

    for (final criterion in criteria) {
      if (!criterion.active) {
        continue;
      }

      total += 1;
      final answer = answers[criterion.id] ?? IrnAnswer.notAnswered;
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

    final answered = notConcerned + nonResilient + intention + medium + result;
    return IrnScoreSummary(
      totalCriteria: total,
      answeredCriteria: answered,
      notConcernedCriteria: notConcerned,
      nonResilientCriteria: nonResilient,
      intentionCriteria: intention,
      mediumCriteria: medium,
      resultCriteria: result,
      notAnsweredCriteria: notAnswered,
      scorePointsTotal: scorePointsTotal,
    );
  }

  /// Calcule la maturité IRN d'un SI à partir des actifs de la campagne.
  ///
  /// Formule officielle intégrée :
  /// - E = pré-score de chaque actif, calculé par moyenne géométrique des
  ///   scores de piliers RES renseignés ;
  /// - D = criticité de l'actif, de 1 à 4 ;
  /// - score SI = EXP(SOMME(D * LN(E)) / SOMME(D)).
  IrnSystemMaturitySummary computeSystemMaturity(
    IrnReferential referential,
    LocalCampaign campaign,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    if (!campaign.information.isAssetScoped) {
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      final summary = computeSummary(referential, answers);
      return IrnSystemMaturitySummary(
        campaign: campaign,
        aggregateSummary: summary,
        aggregatePillarSummaries: computeSummariesByPillar(
          referential,
          answers,
        ),
        assetScores: const <IrnAssetMaturityScore>[],
        maturityScore: summary.openIrnScore,
        maturityWeightTotal: summary.openIrnScore == null ? 0 : 1,
      );
    }

    final assetScores = <IrnAssetMaturityScore>[
      for (final asset in campaign.information.assets)
        computeAssetMaturity(
          referential: referential,
          asset: asset,
          criterionAnswers: criterionAnswers,
        ),
    ];
    final scoredAssets = assetScores
        .where((assetScore) => assetScore.maturityScore != null)
        .toList(growable: false);
    var weightedLogSum = 0.0;
    var weightTotal = 0;
    for (final assetScore in scoredAssets) {
      final score = assetScore.maturityScore;
      if (score == null || score <= 0) {
        continue;
      }
      final weight = assetScore.criticalityWeight;
      weightedLogSum += weight * math.log(score);
      weightTotal += weight;
    }

    final maturityScore = weightTotal == 0
        ? null
        : math.exp(weightedLogSum / weightTotal);
    return IrnSystemMaturitySummary(
      campaign: campaign,
      aggregateSummary: computeAssetScopedAggregateSummary(
        referential,
        campaign,
        criterionAnswers,
      ),
      aggregatePillarSummaries: computeAssetScopedSummariesByPillar(
        referential,
        campaign,
        criterionAnswers,
      ),
      assetScores: List<IrnAssetMaturityScore>.unmodifiable(assetScores),
      maturityScore: maturityScore,
      maturityWeightTotal: weightTotal,
    );
  }

  IrnAssetMaturityScore computeAssetMaturity({
    required IrnReferential referential,
    required CampaignInformationAsset asset,
    required Map<String, CriterionAnswer> criterionAnswers,
  }) {
    final answers = _answersForAsset(asset.id, criterionAnswers);
    final aggregateSummary = computeSummary(referential, answers);
    final pillarSummaries = computeSummariesByPillar(referential, answers);
    final pillarScores = pillarSummaries.values
        .map((summary) => summary.openIrnScore)
        .whereType<double>()
        .where((score) => score > 0)
        .toList(growable: false);
    final maturityScore = pillarScores.isEmpty
        ? null
        : math.exp(
            pillarScores.fold<double>(
                  0,
                  (total, score) => total + math.log(score),
                ) /
                pillarScores.length,
          );

    return IrnAssetMaturityScore(
      asset: asset,
      aggregateSummary: aggregateSummary,
      pillarSummaries: pillarSummaries,
      maturityScore: maturityScore,
      scoredPillarCount: pillarScores.length,
    );
  }

  IrnScoreSummary computeAssetScopedAggregateSummary(
    IrnReferential referential,
    LocalCampaign campaign,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    if (!campaign.information.isAssetScoped) {
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      return computeSummary(referential, answers);
    }
    return _sumSummaries(<IrnScoreSummary>[
      for (final asset in campaign.information.assets)
        computeSummary(
          referential,
          _answersForAsset(asset.id, criterionAnswers),
        ),
    ]);
  }

  Map<IrnPillar, IrnScoreSummary> computeAssetScopedSummariesByPillar(
    IrnReferential referential,
    LocalCampaign campaign,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    if (!campaign.information.isAssetScoped) {
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      return computeSummariesByPillar(referential, answers);
    }
    return <IrnPillar, IrnScoreSummary>{
      for (final pillar in referential.pillars)
        pillar: _sumSummaries(<IrnScoreSummary>[
          for (final asset in campaign.information.assets)
            computeSummaryForPillar(
              referential,
              pillar.id,
              _answersForAsset(asset.id, criterionAnswers),
            ),
        ]),
    };
  }

  Map<CriterionScope, IrnScoreSummary> computeAssetScopedSummariesByScope(
    IrnReferential referential,
    LocalCampaign campaign,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    if (!campaign.information.isAssetScoped) {
      final answers = <String, IrnAnswer>{
        for (final entry in criterionAnswers.entries)
          entry.key: entry.value.answer,
      };
      return computeSummariesByScope(referential, answers);
    }
    final scopes = <CriterionScope, List<IrnCriterion>>{};
    for (final criterion in referential.criteria) {
      if (!criterion.active) {
        continue;
      }
      scopes
          .putIfAbsent(criterion.scope, () => <IrnCriterion>[])
          .add(criterion);
    }
    final entries = scopes.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    return <CriterionScope, IrnScoreSummary>{
      for (final entry in entries)
        entry.key: _sumSummaries(<IrnScoreSummary>[
          for (final asset in campaign.information.assets)
            computeSummaryForCriteria(
              entry.value,
              _answersForAsset(asset.id, criterionAnswers),
            ),
        ]),
    };
  }

  Map<String, IrnAnswer> _answersForAsset(
    String assetId,
    Map<String, CriterionAnswer> criterionAnswers,
  ) {
    final prefix = 'asset:$assetId:criterion:';
    final answers = <String, IrnAnswer>{};
    for (final entry in criterionAnswers.entries) {
      if (!entry.key.startsWith(prefix)) {
        continue;
      }
      final criterionId = entry.key.substring(prefix.length);
      if (criterionId.isEmpty) {
        continue;
      }
      answers[criterionId] = entry.value.answer;
    }
    return answers;
  }

  IrnScoreSummary _sumSummaries(Iterable<IrnScoreSummary> summaries) {
    var total = 0;
    var answered = 0;
    var notConcerned = 0;
    var nonResilient = 0;
    var intention = 0;
    var medium = 0;
    var result = 0;
    var notAnswered = 0;
    var scorePointsTotal = 0;
    for (final summary in summaries) {
      total += summary.totalCriteria;
      answered += summary.answeredCriteria;
      notConcerned += summary.notConcernedCriteria;
      nonResilient += summary.nonResilientCriteria;
      intention += summary.intentionCriteria;
      medium += summary.mediumCriteria;
      result += summary.resultCriteria;
      notAnswered += summary.notAnsweredCriteria;
      scorePointsTotal += summary.scorePointsTotal;
    }
    return IrnScoreSummary(
      totalCriteria: total,
      answeredCriteria: answered,
      notConcernedCriteria: notConcerned,
      nonResilientCriteria: nonResilient,
      intentionCriteria: intention,
      mediumCriteria: medium,
      resultCriteria: result,
      notAnsweredCriteria: notAnswered,
      scorePointsTotal: scorePointsTotal,
    );
  }
}

class IrnAssetMaturityScore {
  final CampaignInformationAsset asset;
  final IrnScoreSummary aggregateSummary;
  final Map<IrnPillar, IrnScoreSummary> pillarSummaries;
  final double? maturityScore;
  final int scoredPillarCount;

  const IrnAssetMaturityScore({
    required this.asset,
    required this.aggregateSummary,
    required this.pillarSummaries,
    required this.maturityScore,
    required this.scoredPillarCount,
  });

  int get criticalityWeight => asset.criticalityWeight;
  int get totalPillarCount => pillarSummaries.length;

  String get formattedMaturityScore {
    final score = maturityScore;
    if (score == null) {
      return 'N/A';
    }
    return '${score.toStringAsFixed(1)} %';
  }
}

class IrnSystemMaturitySummary {
  final LocalCampaign campaign;
  final IrnScoreSummary aggregateSummary;
  final Map<IrnPillar, IrnScoreSummary> aggregatePillarSummaries;
  final List<IrnAssetMaturityScore> assetScores;
  final double? maturityScore;
  final int maturityWeightTotal;

  const IrnSystemMaturitySummary({
    required this.campaign,
    required this.aggregateSummary,
    required this.aggregatePillarSummaries,
    required this.assetScores,
    required this.maturityScore,
    required this.maturityWeightTotal,
  });

  int get scoredAssetCount => assetScores
      .where((assetScore) => assetScore.maturityScore != null)
      .length;

  int get totalAssetCount => assetScores.length;

  double get completionRate => aggregateSummary.completionRate;

  String get formattedMaturityScore {
    final score = maturityScore;
    if (score == null) {
      return 'N/A';
    }
    return '${score.toStringAsFixed(1)} %';
  }
}
