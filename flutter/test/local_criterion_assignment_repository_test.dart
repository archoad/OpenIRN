import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_criterion_assignment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalCriterionAssignmentRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('assigns one criterion to one user', () async {
      const repository = LocalCriterionAssignmentRepository();

      await repository.assignCriterion(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
        criterionId: 'RES-1.1',
        userId: 'user-1',
      );

      final assignments = await repository.loadAssignmentsByCriterion(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );

      expect(assignments['RES-1.1']?.userId, 'user-1');
    });

    test('replaces an existing assignment', () async {
      const repository = LocalCriterionAssignmentRepository();

      await repository.assignCriterion(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
        criterionId: 'RES-1.1',
        userId: 'user-1',
      );
      await repository.assignCriterion(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
        criterionId: 'RES-1.1',
        userId: 'user-2',
      );

      final assignments = await repository.loadAssignments(
        referentialId: 'adri-irn-v1.1',
        campaignId: 'campaign-a',
      );

      expect(assignments, hasLength(1));
      expect(assignments.single.userId, 'user-2');
    });
  });
}
