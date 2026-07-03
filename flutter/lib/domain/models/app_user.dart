import '../utils/openirn_uuid.dart';

enum AppUserRole {
  administrator,
  campaignManager,
  evaluator,
  reviewer,
  reader;

  String get jsonValue {
    switch (this) {
      case AppUserRole.administrator:
        return 'administrator';
      case AppUserRole.campaignManager:
        return 'campaign_manager';
      case AppUserRole.evaluator:
        return 'evaluator';
      case AppUserRole.reviewer:
        return 'reviewer';
      case AppUserRole.reader:
        return 'reader';
    }
  }

  String get label {
    switch (this) {
      case AppUserRole.administrator:
        return 'Administrateur';
      case AppUserRole.campaignManager:
        return 'Pilote IRN';
      case AppUserRole.evaluator:
        return 'Évaluateur';
      case AppUserRole.reviewer:
        return 'Validateur';
      case AppUserRole.reader:
        return 'Lecteur';
    }
  }

  String get description {
    switch (this) {
      case AppUserRole.administrator:
        return 'Gère les utilisateurs, les campagnes et les affectations.';
      case AppUserRole.campaignManager:
        return 'Pilote les campagnes et affecte les critères.';
      case AppUserRole.evaluator:
        return 'Renseigne les réponses et les justifications des critères qui lui sont affectés.';
      case AppUserRole.reviewer:
        return 'Relit les campagnes complètes et peut contribuer à leur validation.';
      case AppUserRole.reader:
        return 'Consulte les campagnes, les synthèses et les exports.';
    }
  }

  static AppUserRole fromJson(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    switch (raw) {
      case 'administrator':
      case 'admin':
      case 'administrateur':
        return AppUserRole.administrator;
      case 'campaign_manager':
      case 'campaignmanager':
      case 'pilot':
      case 'pilote':
      case 'pilote_irn':
        return AppUserRole.campaignManager;
      case 'evaluator':
      case 'evaluateur':
      case 'évaluateur':
        return AppUserRole.evaluator;
      case 'reviewer':
      case 'validator':
      case 'validateur':
        return AppUserRole.reviewer;
      case 'reader':
      case 'lecteur':
      default:
        return AppUserRole.reader;
    }
  }
}

class AppUser {
  // Identifiant historique de l'ancien administrateur local.
  // Il est conservé uniquement pour ignorer proprement les anciens exports.
  static const defaultAdministratorId = 'local-admin';

  final String tenantId;
  final String id;
  final String tenantDisplayName;
  final String firstName;
  final String lastName;
  final String email;
  final AppUserRole role;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    this.tenantId = '',
    required this.id,
    this.tenantDisplayName = '',
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName {
    return <String>[
      firstName.trim(),
      lastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  String get displayName {
    final name = fullName;
    if (name.isNotEmpty && email.trim().isNotEmpty) {
      return '$name <$email>';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (email.trim().isNotEmpty) {
      return email.trim();
    }
    return 'Utilisateur sans nom';
  }

  String get tenantLabel {
    final label = tenantDisplayName.trim();
    return label.isEmpty ? 'Espace de travail' : label;
  }

  factory AppUser.create({
    required String firstName,
    required String lastName,
    required String email,
    required AppUserRole role,
    String tenantId = '',
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return AppUser(
      tenantId: tenantId.trim(),
      id: newOpenIrnUuid(),
      tenantDisplayName: '',
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim().toLowerCase(),
      role: role,
      active: true,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final createdAt =
        _parseDate(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAt = _parseDate(json['updatedAt']) ?? createdAt;
    return AppUser(
      tenantId: json['tenantId']?.toString().trim() ?? '',
      id: json['id']?.toString() ?? '',
      tenantDisplayName: json['tenantDisplayName']?.toString().trim() ?? '',
      firstName: json['firstName']?.toString().trim() ?? '',
      lastName: json['lastName']?.toString().trim() ?? '',
      email: json['email']?.toString().trim().toLowerCase() ?? '',
      role: AppUserRole.fromJson(json['role']),
      active: json['active'] is bool ? json['active'] as bool : true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  AppUser copyWith({
    String? tenantDisplayName,
    String? firstName,
    String? lastName,
    String? email,
    AppUserRole? role,
    bool? active,
    DateTime? updatedAt,
    String? tenantId,
  }) {
    return AppUser(
      tenantId: tenantId?.trim() ?? this.tenantId,
      id: id,
      tenantDisplayName: tenantDisplayName?.trim() ?? this.tenantDisplayName,
      firstName: firstName?.trim() ?? this.firstName,
      lastName: lastName?.trim() ?? this.lastName,
      email: email?.trim().toLowerCase() ?? this.email,
      role: role ?? this.role,
      active: active ?? this.active,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (tenantId.trim().isNotEmpty) 'tenantId': tenantId.trim(),
      if (tenantDisplayName.trim().isNotEmpty)
        'tenantDisplayName': tenantDisplayName.trim(),
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'role': role.jsonValue,
      'roleLabel': role.label,
      'active': active,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
