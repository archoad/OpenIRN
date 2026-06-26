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

class CampaignInformation {
  final String systemName;
  final String systemDescription;
  final String projectDirectorFirstName;
  final String projectDirectorLastName;
  final String projectDirectorEmail;

  const CampaignInformation({
    this.systemName = '',
    this.systemDescription = '',
    this.projectDirectorFirstName = '',
    this.projectDirectorLastName = '',
    this.projectDirectorEmail = '',
  });

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
    return [projectDirectorFirstName.trim(), projectDirectorLastName.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  factory CampaignInformation.fromJson(Map<String, dynamic> json) {
    return CampaignInformation(
      systemName: json['systemName']?.toString().trim() ?? '',
      systemDescription: json['systemDescription']?.toString().trim() ?? '',
      projectDirectorFirstName:
          json['projectDirectorFirstName']?.toString().trim() ?? '',
      projectDirectorLastName:
          json['projectDirectorLastName']?.toString().trim() ?? '',
      projectDirectorEmail:
          json['projectDirectorEmail']?.toString().trim() ?? '',
    );
  }

  CampaignInformation copyWith({
    String? systemName,
    String? systemDescription,
    String? projectDirectorFirstName,
    String? projectDirectorLastName,
    String? projectDirectorEmail,
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
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'systemName': systemName.trim(),
      'systemDescription': systemDescription.trim(),
      'projectDirectorFirstName': projectDirectorFirstName.trim(),
      'projectDirectorLastName': projectDirectorLastName.trim(),
      'projectDirectorEmail': projectDirectorEmail.trim(),
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
    final safeReferentialId = _safeIdPart(referentialId);
    final safeTimestamp =
        timestamp.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');

    return LocalCampaign(
      id: 'local-$safeReferentialId-$safeTimestamp',
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
    final safeReferentialId = _safeIdPart(referentialId);

    return LocalCampaign(
      id: 'local-default-$safeReferentialId',
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
    final createdAt = _parseDate(json['createdAt']) ??
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
        ? projectDirectorPayload
            .map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};

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
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  static String _safeIdPart(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
