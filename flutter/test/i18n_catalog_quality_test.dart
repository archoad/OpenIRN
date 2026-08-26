import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Spanish and German keep the reviewed IRN terminology', () {
    final spanish = _loadCatalog('assets/i18n/es.json');
    final german = _loadCatalog('assets/i18n/de.json');

    expect(spanish['action.refresh'], 'Actualizar');
    expect(spanish['action.reset'], 'Restablecer');
    expect(spanish['assessment.score.completion'], 'Completitud: {rate} %');
    expect(
      spanish['official.scoring.asset_maturity'],
      'Madurez IRN por activos',
    );
    expect(
      spanish['screen.summary.action.export_pdf'],
      'Exportar el resumen en PDF',
    );
    expect(spanish['pdf.summary.method_title'], 'Nota metodológica');

    expect(german['action.refresh'], 'Aktualisieren');
    expect(german['action.reset'], 'Zurücksetzen');
    expect(german['official.scoring.asset_maturity'], 'IRN-Reife nach Assets');
    expect(
      german['screen.summary.action.export_pdf'],
      'Zusammenfassung als PDF exportieren',
    );
    expect(german['pdf.summary.method_title'], 'Methodischer Hinweis');
  });

  test('reviewed catalogs do not regress to known mistranslations', () {
    final spanishText = _loadCatalog('assets/i18n/es.json').values.join('\n');
    final germanText = _loadCatalog('assets/i18n/de.json').values.join('\n');

    for (final mistranslation in [
      'partitura',
      'Terminación',
      'IRN vencimiento',
      'Bienes para IS',
    ]) {
      expect(spanishText, isNot(contains(mistranslation)));
    }
    for (final mistranslation in [
      'IRN Laufzeit',
      'IS-Fälligkeitsbewertung',
      'kostenlose Kampagne',
      'Anzeigegeräten',
    ]) {
      expect(germanText, isNot(contains(mistranslation)));
    }
  });

  test('straight and typographic quotation marks remain balanced', () {
    for (final language in ['es', 'de']) {
      final catalog = _loadCatalog('assets/i18n/$language.json');
      for (final entry in catalog.entries) {
        expect(
          '"'.allMatches(entry.value).length.isEven,
          isTrue,
          reason: '$language:${entry.key} has unbalanced straight quotes',
        );
        if (language == 'es') {
          expect(
            '“'.allMatches(entry.value).length,
            '”'.allMatches(entry.value).length,
            reason: '$language:${entry.key} has unbalanced curly quotes',
          );
        } else {
          expect(
            '„'.allMatches(entry.value).length,
            '“'.allMatches(entry.value).length,
            reason: '$language:${entry.key} has unbalanced German quotes',
          );
        }
        expect(
          '«'.allMatches(entry.value).length,
          '»'.allMatches(entry.value).length,
          reason: '$language:${entry.key} has unbalanced angle quotes',
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
