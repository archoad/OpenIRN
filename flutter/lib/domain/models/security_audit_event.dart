class SecurityAuditEvent {
  final String source;
  final String eventId;
  final String tenantId;
  final String deviceId;
  final String eventType;
  final DateTime? createdAt;
  final String userId;
  final String ipAddress;
  final bool? successful;
  final String reason;
  final Map<String, dynamic> payload;

  const SecurityAuditEvent({
    required this.source,
    required this.eventId,
    required this.tenantId,
    required this.deviceId,
    required this.eventType,
    required this.createdAt,
    required this.userId,
    required this.ipAddress,
    required this.successful,
    required this.reason,
    required this.payload,
  });

  factory SecurityAuditEvent.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return SecurityAuditEvent(
      source: json['source']?.toString() ?? '',
      eventId: json['eventId']?.toString() ?? '',
      tenantId: json['tenantId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? '',
      createdAt: DateTime.tryParse(
        json['createdAt']?.toString() ?? '',
      )?.toUtc(),
      userId: json['userId']?.toString() ?? '',
      ipAddress: json['ipAddress']?.toString() ?? '',
      successful: json.containsKey('successful')
          ? json['successful'] == true
          : null,
      reason: json['reason']?.toString() ?? '',
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
    );
  }

  bool get isAuthAttempt => source == 'authAttempt';
  bool get isDeviceAudit => source == 'deviceAudit';
  bool get isSuccess => successful == true;
  bool get isFailure => successful == false;

  String get sourceLabel {
    if (isAuthAttempt) {
      return 'Authentification';
    }
    if (isDeviceAudit) {
      return 'Terminal';
    }
    return source.isEmpty ? 'Événement' : source;
  }

  String get title {
    if (isAuthAttempt) {
      if (isSuccess) {
        return 'Authentification réussie';
      }
      if (reason.startsWith('rate_limited')) {
        return 'Authentification limitée';
      }
      return 'Authentification refusée';
    }

    switch (eventType) {
      case 'device.enrollment.created':
        return 'Invitation terminal créée';
      case 'device.enrolled':
        return 'Terminal enrôlé';
      case 'device.renamed':
        return 'Terminal renommé';
      case 'device.revoked':
        return 'Terminal révoqué';
      case 'session.created':
        return 'Session créée';
      case 'session.revoked':
        return 'Session révoquée';
      case 'auth.failed':
        return 'Échec d’authentification';
      case 'auth.rate_limited':
        return 'Limitation anti-bruteforce';
      case 'user.initial_pin_invalidated':
        return 'Code initial prévisible invalidé';
      case 'user.pin_change_required':
        return 'Changement de code requis';
      case 'user.pin_changed_on_first_login':
        return 'Code personnel défini à la première connexion';
      case 'user.pin_change_failed':
        return 'Échec du changement de code';
      case 'user.pin_changed':
        return 'Code personnel modifié';
      case 'user.pin_reset_by_administrator':
        return 'Code temporaire attribué par un administrateur';
    }
    return eventType.isEmpty ? 'Événement sécurité' : eventType;
  }

  String get subtitle {
    final parts = <String>[];
    if (deviceId.trim().isNotEmpty) {
      parts.add('Terminal $deviceId');
    }
    if (userId.trim().isNotEmpty) {
      parts.add('Utilisateur $userId');
    }
    if (ipAddress.trim().isNotEmpty) {
      parts.add('IP $ipAddress');
    }
    if (reason.trim().isNotEmpty) {
      parts.add(reason);
    }
    return parts.isEmpty ? 'Aucun détail complémentaire.' : parts.join(' — ');
  }
}
