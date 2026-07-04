import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';

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
}
