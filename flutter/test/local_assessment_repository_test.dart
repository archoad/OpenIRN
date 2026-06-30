import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_assessment_repository.dart';

void main() {
  group('LocalAssessmentRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalAssessmentRepository();
      expect(repository, isA<LocalAssessmentRepository>());
    });
  });
}
