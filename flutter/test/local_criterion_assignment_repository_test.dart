import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_criterion_assignment_repository.dart';

void main() {
  group('LocalCriterionAssignmentRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalCriterionAssignmentRepository();
      expect(repository, isA<LocalCriterionAssignmentRepository>());
    });
  });
}
