class AuthorizedDeviceWorkspace {
  final String tenantId;
  final String tenantDisplayName;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  const AuthorizedDeviceWorkspace({
    required this.tenantId,
    required this.tenantDisplayName,
    required this.status,
    required this.createdAt,
    required this.lastSeenAt,
    required this.revokedAt,
  });

  bool get isActive => status.toLowerCase() == 'active';

  String get tenantLabel {
    final label = tenantDisplayName.trim();
    return label.isEmpty ? 'Espace de travail' : label;
  }

  factory AuthorizedDeviceWorkspace.fromJson(Map<String, dynamic> json) {
    return AuthorizedDeviceWorkspace(
      tenantId: json['tenantId']?.toString() ?? '',
      tenantDisplayName: json['tenantDisplayName']?.toString().trim() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: AuthorizedDevice._parseDate(json['createdAt']),
      lastSeenAt: AuthorizedDevice._parseDate(json['lastSeenAt']),
      revokedAt: AuthorizedDevice._parseDate(json['revokedAt']),
    );
  }
}

class AuthorizedDevice {
  final String tenantId;
  final String deviceId;
  final String tenantDisplayName;
  final String name;
  final String platform;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final String invitedByUserId;
  final String invitedByUserDisplayName;
  final String enrollmentId;
  final List<AuthorizedDeviceWorkspace> workspaces;

  const AuthorizedDevice({
    required this.tenantId,
    required this.deviceId,
    this.tenantDisplayName = '',
    required this.name,
    required this.platform,
    required this.status,
    required this.createdAt,
    required this.lastSeenAt,
    required this.revokedAt,
    required this.invitedByUserId,
    this.invitedByUserDisplayName = '',
    required this.enrollmentId,
    this.workspaces = const <AuthorizedDeviceWorkspace>[],
  });

  bool get isActive => status.toLowerCase() == 'active';

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Terminal OpenIRN' : trimmed;
  }

  String get tenantLabel {
    final label = tenantDisplayName.trim();
    return label.isEmpty ? 'Espace de travail' : label;
  }

  List<AuthorizedDeviceWorkspace> get effectiveWorkspaces {
    if (workspaces.isNotEmpty) {
      return workspaces;
    }
    return <AuthorizedDeviceWorkspace>[
      AuthorizedDeviceWorkspace(
        tenantId: tenantId,
        tenantDisplayName: tenantLabel,
        status: status,
        createdAt: createdAt,
        lastSeenAt: lastSeenAt,
        revokedAt: revokedAt,
      ),
    ];
  }

  int get workspaceCount => effectiveWorkspaces
      .where((workspace) => workspace.tenantId.trim().isNotEmpty)
      .length;

  String get workspaceSummary {
    final labels = effectiveWorkspaces
        .map((workspace) => workspace.tenantLabel)
        .where((label) => label.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (labels.isEmpty) {
      return tenantLabel;
    }
    return labels.join(', ');
  }

  String get invitedByLabel {
    final label = invitedByUserDisplayName.trim();
    return label.isEmpty ? 'Utilisateur' : label;
  }

  String get platformLabel {
    final normalized = platform.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Plateforme non renseignée';
    }
    switch (normalized) {
      case 'ios':
        return 'iOS';
      case 'ipados':
        return 'iPadOS';
      case 'android':
        return 'Android';
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
    }
    return platform.trim();
  }

  String get statusLabel => isActive ? 'Actif' : 'Révoqué';

  factory AuthorizedDevice.fromJson(Map<String, dynamic> json) {
    final rawWorkspaces = json['tenants'];
    final workspaces = rawWorkspaces is List
        ? rawWorkspaces
              .whereType<Map>()
              .map(
                (item) => AuthorizedDeviceWorkspace.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((workspace) => workspace.tenantId.trim().isNotEmpty)
              .toList(growable: false)
        : const <AuthorizedDeviceWorkspace>[];
    return AuthorizedDevice(
      tenantId: json['tenantId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      tenantDisplayName: json['tenantDisplayName']?.toString().trim() ?? '',
      name: json['name']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: _parseDate(json['createdAt']),
      lastSeenAt: _parseDate(json['lastSeenAt']),
      revokedAt: _parseDate(json['revokedAt']),
      invitedByUserId: json['invitedByUserId']?.toString() ?? '',
      invitedByUserDisplayName:
          json['invitedByUserDisplayName']?.toString().trim() ?? '',
      enrollmentId: json['enrollmentId']?.toString() ?? '',
      workspaces: workspaces,
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
