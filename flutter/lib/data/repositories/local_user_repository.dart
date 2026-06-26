import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_user.dart';

class LocalUserRepository {
  const LocalUserRepository();

  static const _schemaVersion = 1;
  static const _storageKey = 'openirn.localUsers';

  Future<List<AppUser>> loadUsers() async {
    final preferences = await SharedPreferences.getInstance();
    final rawPayload = preferences.getString(_storageKey);
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return <AppUser>[];
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return <AppUser>[];
      }
      final rawUsers = decoded['users'];
      if (rawUsers is! List) {
        return <AppUser>[];
      }

      final users = <AppUser>[];
      for (final rawUser in rawUsers) {
        if (rawUser is! Map) {
          continue;
        }
        final user = AppUser.fromJson(rawUser.map((key, value) => MapEntry(key.toString(), value)));
        if (user.id.trim().isEmpty) {
          continue;
        }
        users.add(user);
      }

      users.sort((a, b) {
        if (a.isDefaultAdministrator) {
          return -1;
        }
        if (b.isDefaultAdministrator) {
          return 1;
        }
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
      return users;
    } on FormatException {
      return <AppUser>[];
    }
  }

  Future<List<AppUser>> ensureDefaultUsers() async {
    final users = await loadUsers();
    final hasDefaultAdmin = users.any((user) => user.id == AppUser.defaultAdministratorId);
    if (hasDefaultAdmin) {
      return users;
    }

    final updated = <AppUser>[AppUser.defaultAdministrator(), ...users];
    await saveUsers(updated);
    return updated;
  }

  Future<AppUser> createUser({
    required String firstName,
    required String lastName,
    required String email,
    required AppUserRole role,
  }) async {
    final users = await ensureDefaultUsers();
    final normalizedEmail = email.trim().toLowerCase();
    final existing = users.where((user) => user.email == normalizedEmail);
    if (existing.isNotEmpty) {
      throw const LocalUserRepositoryException('Un utilisateur avec cet email existe déjà.');
    }

    final user = AppUser.create(
      firstName: firstName,
      lastName: lastName,
      email: normalizedEmail,
      role: role,
    );
    await saveUsers(<AppUser>[...users, user]);
    return user;
  }

  Future<AppUser?> updateUser(AppUser updatedUser) async {
    final users = await ensureDefaultUsers();
    final now = DateTime.now().toUtc();
    AppUser? savedUser;
    final updated = <AppUser>[];

    for (final user in users) {
      if (user.id == updatedUser.id) {
        savedUser = updatedUser.copyWith(updatedAt: now);
        updated.add(savedUser);
      } else {
        updated.add(user);
      }
    }

    if (savedUser == null) {
      return null;
    }
    await saveUsers(updated);
    return savedUser;
  }

  Future<void> deleteUser({required String userId}) async {
    if (userId == AppUser.defaultAdministratorId) {
      throw const LocalUserRepositoryException('L’administrateur local ne peut pas être supprimé.');
    }
    final users = await ensureDefaultUsers();
    await saveUsers(users.where((user) => user.id != userId).toList(growable: false));
  }

  Future<void> saveUsers(List<AppUser> users) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'users': <Map<String, dynamic>>[
        for (final user in users) user.toJson(),
      ],
    };
    await preferences.setString(_storageKey, jsonEncode(payload));
  }
}

class LocalUserRepositoryException implements Exception {
  final String message;

  const LocalUserRepositoryException(this.message);

  @override
  String toString() => message;
}
