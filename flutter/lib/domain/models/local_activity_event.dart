enum LocalActivityType {
  campaignCreated,
  campaignDeleted,
  campaignStatusChanged,
  campaignInformationUpdated,
  assignmentChanged,
  answerChanged,
  justificationChanged,
  answersReset;

  String get jsonValue {
    switch (this) {
      case LocalActivityType.campaignCreated:
        return 'campaign_created';
      case LocalActivityType.campaignDeleted:
        return 'campaign_deleted';
      case LocalActivityType.campaignStatusChanged:
        return 'campaign_status_changed';
      case LocalActivityType.campaignInformationUpdated:
        return 'campaign_information_updated';
      case LocalActivityType.assignmentChanged:
        return 'assignment_changed';
      case LocalActivityType.answerChanged:
        return 'answer_changed';
      case LocalActivityType.justificationChanged:
        return 'justification_changed';
      case LocalActivityType.answersReset:
        return 'answers_reset';
    }
  }

  String get label {
    switch (this) {
      case LocalActivityType.campaignCreated:
        return 'Création';
      case LocalActivityType.campaignDeleted:
        return 'Suppression';
      case LocalActivityType.campaignStatusChanged:
        return 'Statut';
      case LocalActivityType.campaignInformationUpdated:
        return 'Informations';
      case LocalActivityType.assignmentChanged:
        return 'Affectation';
      case LocalActivityType.answerChanged:
        return 'Réponse';
      case LocalActivityType.justificationChanged:
        return 'Justification';
      case LocalActivityType.answersReset:
        return 'Réinitialisation';
    }
  }

  static LocalActivityType fromJson(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    switch (raw) {
      case 'campaign_created':
        return LocalActivityType.campaignCreated;
      case 'campaign_deleted':
        return LocalActivityType.campaignDeleted;
      case 'campaign_status_changed':
        return LocalActivityType.campaignStatusChanged;
      case 'campaign_information_updated':
        return LocalActivityType.campaignInformationUpdated;
      case 'assignment_changed':
        return LocalActivityType.assignmentChanged;
      case 'answer_changed':
        return LocalActivityType.answerChanged;
      case 'justification_changed':
        return LocalActivityType.justificationChanged;
      case 'answers_reset':
        return LocalActivityType.answersReset;
      default:
        return LocalActivityType.answerChanged;
    }
  }
}

class LocalActivityEvent {
  final String id;
  final String referentialId;
  final String campaignId;
  final LocalActivityType type;
  final String title;
  final String description;
  final String? criterionId;
  final String? fromValue;
  final String? toValue;
  final DateTime createdAt;

  const LocalActivityEvent({
    required this.id,
    required this.referentialId,
    required this.campaignId,
    required this.type,
    required this.title,
    required this.description,
    required this.createdAt,
    this.criterionId,
    this.fromValue,
    this.toValue,
  });

  factory LocalActivityEvent.create({
    required String referentialId,
    required String campaignId,
    required LocalActivityType type,
    required String title,
    String description = '',
    String? criterionId,
    String? fromValue,
    String? toValue,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final safeTimestamp = timestamp.toIso8601String().replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
    final safeType = type.jsonValue.replaceAll(RegExp(r'[^a-z0-9]+'), '-');

    return LocalActivityEvent(
      id: 'activity-$safeTimestamp-$safeType',
      referentialId: referentialId,
      campaignId: campaignId,
      type: type,
      title: title.trim().isEmpty ? type.label : title.trim(),
      description: description.trim(),
      criterionId: _blankToNull(criterionId),
      fromValue: _blankToNull(fromValue),
      toValue: _blankToNull(toValue),
      createdAt: timestamp,
    );
  }

  factory LocalActivityEvent.fromJson(Map<String, dynamic> json) {
    final createdAt = _parseDate(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    return LocalActivityEvent(
      id: json['id']?.toString() ?? '',
      referentialId: json['referentialId']?.toString() ?? '',
      campaignId: json['campaignId']?.toString() ?? '',
      type: LocalActivityType.fromJson(json['type']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      criterionId: _blankToNull(json['criterionId']?.toString()),
      fromValue: _blankToNull(json['fromValue']?.toString()),
      toValue: _blankToNull(json['toValue']?.toString()),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'referentialId': referentialId,
      'campaignId': campaignId,
      'type': type.jsonValue,
      'title': title,
      'description': description,
      if (criterionId != null) 'criterionId': criterionId,
      if (fromValue != null) 'fromValue': fromValue,
      if (toValue != null) 'toValue': toValue,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
