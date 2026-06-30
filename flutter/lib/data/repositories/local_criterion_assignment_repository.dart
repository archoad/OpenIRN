import '../../domain/models/criterion_assignment.dart';
import 'server_campaign_store.dart';

class LocalCriterionAssignmentRepository {
  final ServerCampaignStore _store;

  const LocalCriterionAssignmentRepository({ServerCampaignStore? store})
    : _store = store ?? const ServerCampaignStore();

  Future<List<CriterionAssignment>> loadAssignments({
    required String referentialId,
    required String campaignId,
  }) async {
    final bundle = await _store.loadBundle(
      referentialId: referentialId,
      campaignId: campaignId,
    );
    return List<CriterionAssignment>.from(
      bundle?.assignments ?? const <CriterionAssignment>[],
    )..sort((a, b) => a.criterionId.compareTo(b.criterionId));
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
    final now = DateTime.now().toUtc();
    late CriterionAssignment savedAssignment;

    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) {
        final existing = bundle.assignments
            .where((assignment) => assignment.criterionId == criterionId)
            .toList(growable: false);
        final next = <CriterionAssignment>[];
        if (existing.isEmpty) {
          savedAssignment = CriterionAssignment.create(
            referentialId: referentialId,
            campaignId: campaignId,
            criterionId: criterionId,
            userId: userId,
            assignedByUserId: assignedByUserId,
            now: now,
          );
          next.addAll(bundle.assignments);
          next.add(savedAssignment);
        } else {
          savedAssignment = existing.first.copyWith(
            userId: userId,
            assignedByUserId: assignedByUserId,
            updatedAt: now,
          );
          for (final assignment in bundle.assignments) {
            next.add(
              assignment.criterionId == criterionId
                  ? savedAssignment
                  : assignment,
            );
          }
        }
        return bundle.copyWith(assignments: next);
      },
    );

    return savedAssignment;
  }

  Future<void> clearAssignment({
    required String referentialId,
    required String campaignId,
    required String criterionId,
  }) async {
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) => bundle.copyWith(
        assignments: bundle.assignments
            .where((assignment) => assignment.criterionId != criterionId)
            .toList(growable: false),
      ),
    );
  }

  Future<void> saveAssignments({
    required String referentialId,
    required String campaignId,
    required List<CriterionAssignment> assignments,
  }) async {
    await _store.updateBundle(
      referentialId: referentialId,
      campaignId: campaignId,
      update: (bundle) => bundle.copyWith(
        assignments: assignments
            .where(
              (assignment) =>
                  assignment.referentialId == referentialId &&
                  assignment.campaignId == campaignId,
            )
            .toList(growable: false),
      ),
    );
  }
}
