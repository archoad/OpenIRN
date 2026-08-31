import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/l10n/openirn_localizations.dart';

void main() {
  test('declared languages and bundled catalog assets stay aligned', () {
    final languages = OpenIrnLanguage.values;
    final codes = languages.map((language) => language.code).toList();
    final labels = languages.map((language) => language.label).toList();
    final catalogCodes =
        Directory('assets/i18n')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .map((file) => file.uri.pathSegments.last.replaceAll('.json', ''))
            .toList()
          ..sort();
    final declaredCodes = [...codes]..sort();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      codes.toSet(),
      hasLength(codes.length),
      reason: 'duplicate language code',
    );
    expect(
      labels.toSet(),
      hasLength(labels.length),
      reason: 'duplicate language label',
    );
    expect(catalogCodes, declaredCodes);
    for (final code in codes) {
      expect(
        pubspec,
        contains('- assets/i18n/$code.json'),
        reason: '$code catalog is not bundled in pubspec.yaml',
      );
    }
  });

  test(
    'all language catalogs expose the same non-empty keys and parameters',
    () {
      final french = _loadCatalog('assets/i18n/fr.json');

      for (final language in OpenIrnLanguage.values) {
        final catalog = _loadCatalog('assets/i18n/${language.code}.json');
        expect(
          catalog.keys.toSet(),
          french.keys.toSet(),
          reason: '${language.code} catalog keys differ from French',
        );
        for (final key in french.keys) {
          expect(
            catalog[key]!.trim(),
            isNotEmpty,
            reason: '${language.code} translation is empty for $key',
          );
          expect(
            _parameters(catalog[key]!),
            _parameters(french[key]!),
            reason: '${language.code} translation parameters differ for $key',
          );
        }
      }
    },
  );

  test('catalogs do not contain duplicate JSON keys', () {
    for (final language in OpenIrnLanguage.values) {
      final path = 'assets/i18n/${language.code}.json';
      final source = File(path).readAsStringSync();
      final keys = RegExp(
        r'^\s*"([^"]+)"\s*:',
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)!).toList();

      expect(
        keys.toSet(),
        hasLength(keys.length),
        reason: '$path contains a duplicate JSON key',
      );
      expect(
        keys.length,
        _loadCatalog(path).length,
        reason: '$path contains a key that the JSON parser overwrote',
      );
    }
  });

  test('literal translation keys used by Dart sources exist', () {
    final french = _loadCatalog('assets/i18n/fr.json');
    final sourceFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final directTranslation = RegExp(
      r'''(?:\.tr|translate)\(\s*['"]([^'"]+)['"]''',
      multiLine: true,
    );

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      for (final match in directTranslation.allMatches(source)) {
        final key = match.group(1)!;
        if (key.contains(r'$')) {
          continue;
        }
        expect(
          french,
          contains(key),
          reason: '${file.path} uses missing translation key $key',
        );
      }
    }
  });

  test('legacy literal translations remain backed by the French catalog', () {
    final frenchValues = _loadCatalog(
      'assets/i18n/fr.json',
    ).values.map((value) => value.trim()).toSet();
    final sourceFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final legacyTranslation = RegExp(
      r'''\.trText\(\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")''',
      multiLine: true,
    );

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      for (final match in legacyTranslation.allMatches(source)) {
        final literal = match.group(1)!;
        final value = _decodeSimpleDartString(literal);
        if (value.contains(r'$')) {
          continue;
        }
        expect(
          frenchValues,
          contains(value.trim()),
          reason: '${file.path} uses an untranslated legacy literal: $value',
        );
      }
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

String _decodeSimpleDartString(String literal) {
  return literal
      .substring(1, literal.length - 1)
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\\', r'\');
}
