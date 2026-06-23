class OrganizationEntity {
  final String id;
  final String name;

  const OrganizationEntity({required this.id, required this.name});
}

class BusinessFunction {
  final String id;
  final String name;
  final String entityId;

  const BusinessFunction(
      {required this.id, required this.name, required this.entityId});
}

class CriticalSystem {
  final String id;
  final String name;
  final String businessFunctionId;

  const CriticalSystem(
      {required this.id, required this.name, required this.businessFunctionId});
}

class TechnicalFunction {
  final String id;
  final String name;
  final String criticalSystemId;

  const TechnicalFunction(
      {required this.id, required this.name, required this.criticalSystemId});
}

class Asset {
  final String id;
  final String name;
  final String technicalFunctionId;

  const Asset(
      {required this.id,
      required this.name,
      required this.technicalFunctionId});
}

class HarmonizedAsset {
  final String id;
  final String name;
  final List<String> sourceAssetIds;
  final double criticalityWeight;

  const HarmonizedAsset({
    required this.id,
    required this.name,
    this.sourceAssetIds = const [],
    this.criticalityWeight = 1,
  });
}
