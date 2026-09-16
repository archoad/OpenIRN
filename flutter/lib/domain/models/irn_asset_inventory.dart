class CriticalFunctionInfo {
  final String id;
  final String tenantId;
  final String name;
  final String description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CriticalFunctionInfo({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory CriticalFunctionInfo.fromJson(Map<String, dynamic> json) {
    return CriticalFunctionInfo(
      id: json['functionId']?.toString() ?? json['id']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toUtc(),
      updatedAt: DateTime.tryParse(
        json['updatedAt']?.toString() ?? '',
      )?.toUtc(),
    );
  }
}

class InformationSystemInfo {
  final String id;
  final String tenantId;
  final List<String> functionIds;
  final String name;
  final String description;
  final String owner;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InformationSystemInfo({
    required this.id,
    required this.tenantId,
    required this.functionIds,
    required this.name,
    required this.description,
    required this.owner,
    this.createdAt,
    this.updatedAt,
  });

  String get functionId => functionIds.isEmpty ? '' : functionIds.first;

  factory InformationSystemInfo.fromJson(Map<String, dynamic> json) {
    return InformationSystemInfo(
      id: json['systemId']?.toString() ?? json['id']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      functionIds: _relationIds(json['functionIds'], json['functionId']),
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      owner: json['owner']?.toString().trim() ?? '',
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toUtc(),
      updatedAt: DateTime.tryParse(
        json['updatedAt']?.toString() ?? '',
      )?.toUtc(),
    );
  }
}

class InformationAssetInfo {
  final String id;
  final String tenantId;
  final List<String> systemIds;
  final String name;
  final String assetType;
  final String description;
  final String criticality;
  final int assessmentAnswerCount;
  final DateTime? assessmentUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InformationAssetInfo({
    required this.id,
    required this.tenantId,
    required this.systemIds,
    required this.name,
    required this.assetType,
    required this.description,
    required this.criticality,
    this.assessmentAnswerCount = 0,
    this.assessmentUpdatedAt,
    this.createdAt,
    this.updatedAt,
  });

  String get systemId => systemIds.isEmpty ? '' : systemIds.first;
  bool get isAssessed => assessmentAnswerCount > 0;

  factory InformationAssetInfo.fromJson(Map<String, dynamic> json) {
    return InformationAssetInfo(
      id: json['assetId']?.toString() ?? json['id']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      systemIds: _relationIds(json['systemIds'], json['systemId']),
      name: json['name']?.toString().trim() ?? '',
      assetType: json['assetType']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      criticality: json['criticality']?.toString().trim() ?? '',
      assessmentAnswerCount:
          int.tryParse(json['assessmentAnswerCount']?.toString() ?? '') ?? 0,
      assessmentUpdatedAt: DateTime.tryParse(
        json['assessmentUpdatedAt']?.toString() ?? '',
      )?.toUtc(),
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toUtc(),
      updatedAt: DateTime.tryParse(
        json['updatedAt']?.toString() ?? '',
      )?.toUtc(),
    );
  }
}

class IrnAssetInventory {
  final String tenantId;
  final String tenantDisplayName;
  final List<CriticalFunctionInfo> criticalFunctions;
  final List<InformationSystemInfo> informationSystems;
  final List<InformationAssetInfo> assets;

  const IrnAssetInventory({
    required this.tenantId,
    required this.tenantDisplayName,
    required this.criticalFunctions,
    required this.informationSystems,
    required this.assets,
  });

  factory IrnAssetInventory.empty({
    String tenantId = '',
    String tenantDisplayName = '',
  }) {
    return IrnAssetInventory(
      tenantId: tenantId,
      tenantDisplayName: tenantDisplayName,
      criticalFunctions: const <CriticalFunctionInfo>[],
      informationSystems: const <InformationSystemInfo>[],
      assets: const <InformationAssetInfo>[],
    );
  }

  factory IrnAssetInventory.fromJson(Map<String, dynamic> json) {
    final rawFunctions = json['criticalFunctions'];
    final rawSystems = json['informationSystems'];
    final rawAssets = json['assets'];
    return IrnAssetInventory(
      tenantId: json['tenantId']?.toString() ?? '',
      tenantDisplayName: json['tenantDisplayName']?.toString().trim() ?? '',
      criticalFunctions: rawFunctions is List
          ? rawFunctions
                .whereType<Map>()
                .map(
                  (item) => CriticalFunctionInfo.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.id.trim().isNotEmpty)
                .toList(growable: false)
          : const <CriticalFunctionInfo>[],
      informationSystems: rawSystems is List
          ? rawSystems
                .whereType<Map>()
                .map(
                  (item) => InformationSystemInfo.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.id.trim().isNotEmpty)
                .toList(growable: false)
          : const <InformationSystemInfo>[],
      assets: rawAssets is List
          ? rawAssets
                .whereType<Map>()
                .map(
                  (item) => InformationAssetInfo.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.id.trim().isNotEmpty)
                .toList(growable: false)
          : const <InformationAssetInfo>[],
    );
  }

  List<InformationSystemInfo> systemsForFunction(String functionId) {
    return informationSystems
        .where((system) => system.functionIds.contains(functionId))
        .toList(growable: false);
  }

  List<InformationAssetInfo> assetsForSystem(String systemId) {
    return assets
        .where((asset) => asset.systemIds.contains(systemId))
        .toList(growable: false);
  }
}

List<String> _relationIds(Object? values, Object? legacyValue) {
  final result = <String>[];
  if (values is List) {
    for (final value in values) {
      final id = value?.toString().trim() ?? '';
      if (id.isNotEmpty && !result.contains(id)) {
        result.add(id);
      }
    }
  }
  final legacyId = legacyValue?.toString().trim() ?? '';
  if (legacyId.isNotEmpty && !result.contains(legacyId)) {
    result.add(legacyId);
  }
  return List<String>.unmodifiable(result);
}
