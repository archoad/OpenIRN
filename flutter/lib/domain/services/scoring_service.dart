import '../models/evaluation.dart';

class ScoringService {
  double? officialPercent(List<Evaluation> evaluations) {
    final applicable = evaluations
        .where((e) => e.officialAnswer != OfficialAnswer.notConcerned)
        .toList();
    if (applicable.isEmpty) return null;
    final resilient = applicable
        .where((e) => e.officialAnswer == OfficialAnswer.resilient)
        .length;
    return resilient * 100 / applicable.length;
  }

  double? internalAverage(List<Evaluation> evaluations) {
    final values = evaluations
        .where(
          (e) => e.internalMaturityLevel != InternalMaturityLevel.notConcerned,
        )
        .map((e) => e.internalScore)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double? weightedAverage(Map<double, double> scoreByWeight) {
    if (scoreByWeight.isEmpty) return null;
    var weightedScore = 0.0;
    var totalWeight = 0.0;
    for (final entry in scoreByWeight.entries) {
      weightedScore += entry.key * entry.value;
      totalWeight += entry.value;
    }
    if (totalWeight == 0) return null;
    return weightedScore / totalWeight;
  }
}
