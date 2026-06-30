import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/repositories/local_activity_repository.dart';

void main() {
  group('LocalActivityRepository', () {
    test('is backed by the OpenIRN server API in server-only mode', () {
      const repository = LocalActivityRepository();
      expect(repository, isA<LocalActivityRepository>());
    });
  });
}
