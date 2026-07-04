import '../utils/openirn_uuid.dart';

enum LocalCampaignStatus {
  draft,
  readyForReview,
  validated,
  archived;

  String get jsonValue {
    switch (this) {
      case LocalCampaignStatus.draft:
        return 'draft';
      case LocalCampaignStatus.readyForReview:
        return 'ready_for_review';
      case LocalCampaignStatus.validated:
        return 'validated';
      case LocalCampaignStatus.archived:
        return 'archived';
    }
  }

  String get label {
    switch (this) {
      case LocalCampaignStatus.draft:
        return 'Brouillon';
      case LocalCampaignStatus.readyForReview:
        return 'Prêt pour revue';
      case LocalCampaignStatus.validated:
        return 'Validé';
      case LocalCampaignStatus.archived:
        return 'Archivé';
    }
  }

  String get helperText {
    switch (this) {
      case LocalCampaignStatus.draft:
        return 'La campagne peut encore être complétée.';
      case LocalCampaignStatus.readyForReview:
        return 'La campagne est complète et peut être relue.';
      case LocalCampaignStatus.validated:
        return 'La campagne est validée et passe en lecture seule.';
      case LocalCampaignStatus.archived:
        return 'La campagne est archivée et reste consultable.';
    }
  }

  bool get isReadOnly =>
      this == LocalCampaignStatus.validated ||
      this == LocalCampaignStatus.archived;

  static LocalCampaignStatus fromJson(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    switch (raw) {
      case 'ready_for_review':
      case 'readyforreview':
      case 'ready':
        return LocalCampaignStatus.readyForReview;
      case 'validated':
      case 'validée':
      case 'validee':
        return LocalCampaignStatus.validated;
      case 'archived':
      case 'archivée':
      case 'archivee':
        return LocalCampaignStatus.archived;
      case 'draft':
      case 'brouillon':
      default:
        return LocalCampaignStatus.draft;
    }
  }
}

class CampaignInformationAsset {
  final String id;
  final String name;
  final String assetType;
  final String description;

  const CampaignInformationAsset({
    required this.id,
    required this.name,
    this.assetType = '',
    this.description = '',
  });

  String get displayLabel {
    final cleanName = name.trim();
    if (cleanName.isNotEmpty) {
      return cleanName;
    }
    return id.trim().isEmpty ? 'Actif sans nom' : id.trim();
  }

  factory CampaignInformationAsset.fromJson(Map<String, dynamic> json) {
    return CampaignInformationAsset(
      id:
          json['assetId']?.toString().trim() ??
          json['id']?.toString().trim() ??
          '',
      name: json['name']?.toString().trim() ?? '',
      assetType: json['assetType']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'assetId': id.trim(),
      'name': name.trim(),
      'assetType': assetType.trim(),
      'description': description.trim(),
    };
  }
}

class CampaignInformation {
  final String systemName;
  final String systemDescription;
  final String projectDirectorFirstName;
  final String projectDirectorLastName;
  final String projectDirectorEmail;
  final String criticalFunctionId;
  final String criticalFunctionName;
  final String informationSystemId;
  final List<CampaignInformationAsset> assets;

  const CampaignInformation({
    this.systemName = '',
    this.systemDescription = '',
    this.projectDirectorFirstName = '',
    this.projectDirectorLastName = '',
    this.projectDirectorEmail = '',
    this.criticalFunctionId = '',
    this.criticalFunctionName = '',
    this.informationSystemId = '',
    this.assets = const <CampaignInformationAsset>[],
  });

  bool get isAssetScoped =>
      informationSystemId.trim().isNotEmpty && assets.isNotEmpty;

  CampaignInformationAsset? assetById(String? assetId) {
    final cleanId = assetId?.trim() ?? '';
    if (cleanId.isEmpty) {
      return null;
    }
    for (final asset in assets) {
      if (asset.id == cleanId) {
        return asset;
      }
    }
    return null;
  }

  bool get hasSystemName => systemName.trim().isNotEmpty;
  bool get hasSystemDescription => systemDescription.trim().isNotEmpty;
  bool get hasProjectDirectorFirstName =>
      projectDirectorFirstName.trim().isNotEmpty;
  bool get hasProjectDirectorLastName =>
      projectDirectorLastName.trim().isNotEmpty;
  bool get hasProjectDirectorEmail => projectDirectorEmail.trim().isNotEmpty;

  bool get isComplete =>
      hasSystemName &&
      hasSystemDescription &&
      hasProjectDirectorFirstName &&
      hasProjectDirectorLastName &&
      hasProjectDirectorEmail;

  String get projectDirectorFullName {
    return [
      projectDirectorFirstName.trim(),
      projectDirectorLastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  factory CampaignInformation.fromJson(Map<String, dynamic> json) {
    final scopePayload = json['inventoryScope'];
    final scope = scopePayload is Map
        ? scopePayload.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final rawAssets = scope['assets'] ?? json['assets'];
    final assets = rawAssets is List
        ? rawAssets
              .whereType<Map>()
              .map(
                (item) => CampaignInformationAsset.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((asset) => asset.id.trim().isNotEmpty)
              .toList(growable: false)
        : const <CampaignInformationAsset>[];

    return CampaignInformation(
      systemName: json['systemName']?.toString().trim() ?? '',
      systemDescription: json['systemDescription']?.toString().trim() ?? '',
      projectDirectorFirstName:
          json['projectDirectorFirstName']?.toString().trim() ?? '',
      projectDirectorLastName:
          json['projectDirectorLastName']?.toString().trim() ?? '',
      projectDirectorEmail:
          json['projectDirectorEmail']?.toString().trim() ?? '',
      criticalFunctionId:
          scope['criticalFunctionId']?.toString().trim() ??
          json['criticalFunctionId']?.toString().trim() ??
          '',
      criticalFunctionName:
          scope['criticalFunctionName']?.toString().trim() ??
          json['criticalFunctionName']?.toString().trim() ??
          '',
      informationSystemId:
          scope['informationSystemId']?.toString().trim() ??
          json['informationSystemId']?.toString().trim() ??
          '',
      assets: assets,
    );
  }

  CampaignInformation copyWith({
    String? systemName,
    String? systemDescription,
    String? projectDirectorFirstName,
    String? projectDirectorLastName,
    String? projectDirectorEmail,
    String? criticalFunctionId,
    String? criticalFunctionName,
    String? informationSystemId,
    List<CampaignInformationAsset>? assets,
  }) {
    return CampaignInformation(
      systemName: systemName?.trim() ?? this.systemName,
      systemDescription: systemDescription?.trim() ?? this.systemDescription,
      projectDirectorFirstName:
          projectDirectorFirstName?.trim() ?? this.projectDirectorFirstName,
      projectDirectorLastName:
          projectDirectorLastName?.trim() ?? this.projectDirectorLastName,
      projectDirectorEmail:
          projectDirectorEmail?.trim() ?? this.projectDirectorEmail,
      criticalFunctionId: criticalFunctionId?.trim() ?? this.criticalFunctionId,
      criticalFunctionName:
          criticalFunctionName?.trim() ?? this.criticalFunctionName,
      informationSystemId:
          informationSystemId?.trim() ?? this.informationSystemId,
      assets: assets ?? this.assets,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'systemName': systemName.trim(),
      'systemDescription': systemDescription.trim(),
      'projectDirectorFirstName': projectDirectorFirstName.trim(),
      'projectDirectorLastName': projectDirectorLastName.trim(),
      'projectDirectorEmail': projectDirectorEmail.trim(),
      'inventoryScope': <String, dynamic>{
        'criticalFunctionId': criticalFunctionId.trim(),
        'criticalFunctionName': criticalFunctionName.trim(),
        'informationSystemId': informationSystemId.trim(),
        'assets': assets.map((asset) => asset.toJson()).toList(growable: false),
      },
    };
  }
}

class LocalCampaign {
  final String id;
  final String referentialId;
  final String name;
  final String description;
  final CampaignInformation information;
  final LocalCampaignStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime statusUpdatedAt;

  const LocalCampaign({
    required this.id,
    required this.referentialId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.statusUpdatedAt,
    this.description = '',
    this.information = const CampaignInformation(),
    this.status = LocalCampaignStatus.draft,
  });

  bool get isReadOnly => status.isReadOnly;

  factory LocalCampaign.create({
    required String referentialId,
    required String name,
    String description = '',
    CampaignInformation information = const CampaignInformation(),
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return LocalCampaign(
      id: newOpenIrnUuid(),
      referentialId: referentialId,
      name: name.trim().isEmpty ? 'Évaluation locale' : name.trim(),
      description: description.trim(),
      information: information,
      status: LocalCampaignStatus.draft,
      createdAt: timestamp,
      updatedAt: timestamp,
      statusUpdatedAt: timestamp,
    );
  }

  factory LocalCampaign.defaultForReferential({
    required String referentialId,
    required String referentialVersion,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return LocalCampaign(
      id: newOpenIrnUuid(),
      referentialId: referentialId,
      name: 'Évaluation locale — IRN $referentialVersion',
      description:
          'Campagne créée automatiquement pour tester le référentiel officiel.',
      status: LocalCampaignStatus.draft,
      createdAt: timestamp,
      updatedAt: timestamp,
      statusUpdatedAt: timestamp,
    );
  }

  factory LocalCampaign.fromJson(Map<String, dynamic> json) {
    final createdAt =
        _parseDate(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAt = _parseDate(json['updatedAt']) ?? createdAt;

    return LocalCampaign(
      id: json['id']?.toString() ?? '',
      referentialId: json['referentialId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Évaluation locale',
      description: json['description']?.toString() ?? '',
      information: _informationFromJson(json),
      status: LocalCampaignStatus.fromJson(json['status']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      statusUpdatedAt: _parseDate(json['statusUpdatedAt']) ?? updatedAt,
    );
  }

  LocalCampaign copyWith({
    String? name,
    String? description,
    CampaignInformation? information,
    LocalCampaignStatus? status,
    DateTime? updatedAt,
    DateTime? statusUpdatedAt,
  }) {
    return LocalCampaign(
      id: id,
      referentialId: referentialId,
      name: name ?? this.name,
      description: description ?? this.description,
      information: information ?? this.information,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'referentialId': referentialId,
      'name': name,
      'description': description,
      'information': information.toJson(),
      'systemName': information.systemName,
      'systemDescription': information.systemDescription,
      'projectDirectorFirstName': information.projectDirectorFirstName,
      'projectDirectorLastName': information.projectDirectorLastName,
      'projectDirectorEmail': information.projectDirectorEmail,
      'status': status.jsonValue,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'statusUpdatedAt': statusUpdatedAt.toUtc().toIso8601String(),
    };
  }

  static CampaignInformation _informationFromJson(Map<String, dynamic> json) {
    final informationPayload = json['information'];
    if (informationPayload is Map<String, dynamic>) {
      return CampaignInformation.fromJson(informationPayload);
    }
    if (informationPayload is Map) {
      return CampaignInformation.fromJson(
        informationPayload.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    final systemPayload = json['system'];
    final system = systemPayload is Map
        ? systemPayload.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final projectDirectorPayload = json['projectDirector'];
    final projectDirector = projectDirectorPayload is Map
        ? projectDirectorPayload.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, dynamic>{};

    final scopePayload = json['inventoryScope'];
    final scope = scopePayload is Map
        ? scopePayload.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final rawAssets = scope['assets'] ?? json['assets'];
    final assets = rawAssets is List
        ? rawAssets
              .whereType<Map>()
              .map(
                (item) => CampaignInformationAsset.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((asset) => asset.id.trim().isNotEmpty)
              .toList(growable: false)
        : const <CampaignInformationAsset>[];

    // Compatibilité avec les exports locaux qui exposent les informations
    // sous forme imbriquée ou sous forme de champs à plat.
    return CampaignInformation(
      systemName: system['name']?.toString().trim().isNotEmpty == true
          ? system['name'].toString().trim()
          : json['systemName']?.toString().trim() ?? '',
      systemDescription:
          system['description']?.toString().trim().isNotEmpty == true
          ? system['description'].toString().trim()
          : json['systemDescription']?.toString().trim() ?? '',
      projectDirectorFirstName:
          projectDirector['firstName']?.toString().trim().isNotEmpty == true
          ? projectDirector['firstName'].toString().trim()
          : json['projectDirectorFirstName']?.toString().trim() ?? '',
      projectDirectorLastName:
          projectDirector['lastName']?.toString().trim().isNotEmpty == true
          ? projectDirector['lastName'].toString().trim()
          : json['projectDirectorLastName']?.toString().trim() ?? '',
      projectDirectorEmail:
          projectDirector['email']?.toString().trim().isNotEmpty == true
          ? projectDirector['email'].toString().trim()
          : json['projectDirectorEmail']?.toString().trim() ?? '',
      criticalFunctionId:
          scope['criticalFunctionId']?.toString().trim() ??
          json['criticalFunctionId']?.toString().trim() ??
          '',
      criticalFunctionName:
          scope['criticalFunctionName']?.toString().trim() ??
          json['criticalFunctionName']?.toString().trim() ??
          '',
      informationSystemId:
          scope['informationSystemId']?.toString().trim() ??
          json['informationSystemId']?.toString().trim() ??
          '',
      assets: assets,
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
