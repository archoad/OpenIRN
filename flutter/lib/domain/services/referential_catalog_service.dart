import '../models/irn_referential.dart';

class ReferentialCatalogService {
  const ReferentialCatalogService();

  Map<IrnPillar, List<IrnCriterion>> criteriaByPillar(
      IrnReferential referential) {
    final byPillarId = <String, List<IrnCriterion>>{};
    for (final criterion in referential.criteria) {
      byPillarId
          .putIfAbsent(criterion.pillarId, () => <IrnCriterion>[])
          .add(criterion);
    }

    for (final criteria in byPillarId.values) {
      criteria.sort((a, b) => compareIrnCodes(a.code, b.code));
    }

    return {
      for (final pillar in referential.pillars)
        pillar:
            List.unmodifiable(byPillarId[pillar.id] ?? const <IrnCriterion>[]),
    };
  }

  Map<CriterionScope, int> criteriaCountByScope(IrnReferential referential) {
    final result = <CriterionScope, int>{};
    for (final criterion in referential.criteria) {
      result[criterion.scope] = (result[criterion.scope] ?? 0) + 1;
    }
    return result;
  }

  List<IrnCriterion> searchCriteria(IrnReferential referential, String query) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return referential.criteria;
    }
    return referential.criteria
        .where((criterion) => criterion.matches(normalizedQuery))
        .toList(growable: false);
  }

  List<IrnCriterion> criteriaForPillar(
    IrnReferential referential,
    String pillarId, {
    String query = '',
  }) {
    return searchCriteria(referential, query)
        .where((criterion) => criterion.pillarId == pillarId)
        .toList(growable: false)
      ..sort((a, b) => compareIrnCodes(a.code, b.code));
  }
}
