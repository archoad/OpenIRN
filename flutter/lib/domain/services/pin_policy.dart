bool isPredictableOpenIrnPin(String value) {
  final pin = value.trim();
  final lowered = pin.toLowerCase();
  const weakValues = <String>{
    '0000',
    '1111',
    '1234',
    '4321',
    '0123',
    '2580',
    'password',
    'motdepasse',
  };
  final repeated = pin.isNotEmpty && pin.split('').toSet().length == 1;
  final sequential =
      RegExp(r'^\d+$').hasMatch(pin) &&
      ('01234567890123456789'.contains(pin) ||
          '98765432109876543210'.contains(pin));
  return weakValues.contains(lowered) || repeated || sequential;
}
