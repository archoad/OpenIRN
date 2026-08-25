import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('French and English catalogs expose the same keys and parameters', () {
    final french = _loadCatalog('assets/i18n/fr.json');
    final english = _loadCatalog('assets/i18n/en.json');

    expect(french.keys.toSet(), english.keys.toSet());
    for (final key in french.keys) {
      expect(
        _parameters(french[key]!),
        _parameters(english[key]!),
        reason: 'Translation parameters differ for $key',
      );
    }
  });
}

Map<String, String> _loadCatalog(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync()) as Map;
  return decoded.map(
    (key, value) => MapEntry(key.toString(), value.toString()),
  );
}

Set<String> _parameters(String message) {
  return RegExp(
    r'\{([A-Za-z][A-Za-z0-9_]*)\}',
  ).allMatches(message).map((match) => match.group(1)!).toSet();
}
