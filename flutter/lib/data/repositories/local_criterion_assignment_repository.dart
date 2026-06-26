import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/criterion_assignment.dart';

class LocalCriterionAssignmentRepository {
  const LocalCriterionAssignmentRepository();

  static const _schemaVersion = 1;
  static const _keyPrefix = 'openirn.criterionAssignments';

  Future<List<CriterionAssignment>> loadAssignments({
    required String referentialId,
    required String campaignId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final rawPayload = preferences.getString(
      _storageKey(referentialId, campaignId),
    );
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return <CriterionAssignment>[];
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return <CriterionAssignment>[];
      }
      final rawAssignments = decoded['assignments'];
      if (rawAssignments is! List) {
        return <CriterionAssignment>[];
      }

      final assignments = <CriterionAssignment>[];
      for (final rawAssignment in rawAssignments) {
        if (rawAssignment is! Map) {
          continue;
        }
        final assignment = CriterionAssignment.fromJson(
          rawAssignment.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (assignment.referentialId != referentialId ||
            assignment.campaignId != campaignId) {
          continue;
        }
        if (assignment.criterionId.trim().isEmpty ||
            assignment.userId.trim().isEmpty) {
          continue;
        }
        assignments.add(assignment);
      }
      assignments.sort((a, b) => a.criterionId.compareTo(b.criterionId));
      return assignments;
    } on FormatException {
      return <CriterionAssignment>[];
    }
  }

  Future<Map<String, CriterionAssignment>> loadAssignmentsByCriterion({
    required String referentialId,
    required String campaignId,
  }) async {
    final assignments = await loadAssignments(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    return <String, CriterionAssignment>{
      for (final assignment in assignments) assignment.criterionId: assignment,
    };
  }

  Future<CriterionAssignment> assignCriterion({
    required String referentialId,
    required String campaignId,
    required String criterionId,
    required String userId,
    String assignedByUserId = '',
  }) async {
    final assignments = await loadAssignments(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    final now = DateTime.now().toUtc();
    final existing = assignments
        .where((assignment) => assignment.criterionId == criterionId)
        .toList(growable: false);
    final next = <CriterionAssignment>[];
    CriterionAssignment savedAssignment;

    if (existing.isEmpty) {
      savedAssignment = CriterionAssignment.create(
        referentialId: referentialId,
        campaignId: campaignId,
        criterionId: criterionId,
        userId: userId,
        assignedByUserId: assignedByUserId,
        now: now,
      );
      next.addAll(assignments);
      next.add(savedAssignment);
    } else {
      savedAssignment = existing.first.copyWith(
        userId: userId,
        assignedByUserId: assignedByUserId,
        updatedAt: now,
      );
      for (final assignment in assignments) {
        next.add(
          assignment.criterionId == criterionId ? savedAssignment : assignment,
        );
      }
    }

    await saveAssignments(
      referentialId: referentialId,
      campaignId: campaignId,
      assignments: next,
    );
    return savedAssignment;
  }

  Future<void> clearAssignment({
    required String referentialId,
    required String campaignId,
    required String criterionId,
  }) async {
    final assignments = await loadAssignments(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    await saveAssignments(
      referentialId: referentialId,
      campaignId: campaignId,
      assignments: assignments
          .where((assignment) => assignment.criterionId != criterionId)
          .toList(growable: false),
    );
  }

  Future<void> saveAssignments({
    required String referentialId,
    required String campaignId,
    required List<CriterionAssignment> assignments,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'referentialId': referentialId,
      'campaignId': campaignId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'assignments': <Map<String, dynamic>>[
        for (final assignment in assignments)
          if (assignment.referentialId == referentialId &&
              assignment.campaignId == campaignId)
            assignment.toJson(),
      ],
    };
    await preferences.setString(
      _storageKey(referentialId, campaignId),
      jsonEncode(payload),
    );
  }

  String _storageKey(String referentialId, String campaignId) {
    return '$_keyPrefix.$referentialId.$campaignId';
  }
}
