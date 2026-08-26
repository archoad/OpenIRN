import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/domain/models/irn_assessment.dart';
import 'package:openirn/domain/models/irn_referential.dart';
import 'package:openirn/domain/models/local_campaign.dart';
import 'package:openirn/domain/services/assessment_pdf_export_service.dart';

void main() {
  test(
    'summary PDF obtains all user-facing labels from the active catalog',
    () async {
      final translatedKeys = <String>[];
      String translate(
        String key, {
        String? fallback,
        Map<String, Object?> values = const <String, Object?>{},
      }) {
        translatedKeys.add(key);
        var result =
            <String, String>{
              'screen.summary.title_prefix': 'Resumen — {campaign}',
              'pdf.summary.page': 'OpenIRN — página {current}/{total}',
            }[key] ??
            fallback ??
            key;
        values.forEach((name, value) {
          result = result.replaceAll('{$name}', value.toString());
        });
        return result;
      }

      const referential = IrnReferential(
        id: 'adri-irn-test',
        version: 'vtest',
        source: IrnSource(
          type: 'test',
          url: '',
          projectPath: '',
          defaultBranch: 'main',
          filePath: '',
          license: '',
        ),
        pillars: [],
        criteria: [],
      );
      final timestamp = DateTime.utc(2026, 8, 26, 10);
      final campaign = LocalCampaign(
        id: 'campaign-test',
        referentialId: referential.id,
        name: 'Campaña de prueba',
        status: LocalCampaignStatus.readyForReview,
        createdAt: timestamp,
        updatedAt: timestamp,
        statusUpdatedAt: timestamp,
      );
      const summary = IrnScoreSummary(
        totalCriteria: 0,
        answeredCriteria: 0,
        notConcernedCriteria: 0,
        nonResilientCriteria: 0,
        intentionCriteria: 0,
        mediumCriteria: 0,
        resultCriteria: 0,
        notAnsweredCriteria: 0,
        scorePointsTotal: 0,
      );

      final bytes = await const AssessmentPdfExportService().buildSummaryPdf(
        translate: translate,
        campaign: campaign,
        referential: referential,
        globalSummary: summary,
        pillarSummaries: const {},
        scopeSummaries: const {},
        strongestPillars: const [],
        weakestPillars: const [],
        generatedAt: timestamp,
      );

      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
      expect(
        translatedKeys,
        containsAll(<String>[
          'screen.summary.title_prefix',
          'pdf.summary.subject',
          'pdf.summary.page',
          'campaign.status.ready_for_review',
          'screen.summary.indicators',
          'pdf.summary.radar_table',
          'screen.summary.by_scope',
          'screen.summary.strengths',
          'screen.summary.attention',
          'pdf.summary.method_title',
          'pdf.summary.method_body',
        ]),
      );
    },
  );
}
