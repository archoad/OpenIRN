import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/data/files/local_json_file_service.dart';

void main() {
  test('buildExportFileName produit un nom de fichier JSON sûr', () {
    const service = LocalJsonFileService();

    final fileName = service.buildExportFileName(
      campaignName: 'Évaluation IRN 2026 / SI Critiques',
      referentialVersion: 'v1.1',
      now: DateTime(2026, 6, 22, 16, 45),
    );

    expect(
      fileName,
      'openirn_evaluation_irn_2026_si_critiques_v1_1_20260622_1645.json',
    );
  });
}
