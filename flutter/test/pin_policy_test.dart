import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/services/pin_policy.dart';

void main() {
  test('rejects predictable personal codes', () {
    for (final pin in <String>['0000', '1234', '9876', 'aaaa', 'password']) {
      expect(isPredictableOpenIrnPin(pin), isTrue, reason: pin);
    }
  });

  test('accepts non-trivial personal codes', () {
    expect(isPredictableOpenIrnPin('7391'), isFalse);
    expect(isPredictableOpenIrnPin('G7m2!'), isFalse);
  });
}
