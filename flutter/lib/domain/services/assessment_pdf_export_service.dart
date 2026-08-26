import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';
import 'official_rnr_scoring_service.dart';

typedef AssessmentPdfTranslate =
    String Function(
      String key, {
      String? fallback,
      Map<String, Object?> values,
    });

class AssessmentPdfExportService {
  const AssessmentPdfExportService();

  Future<Uint8List> buildSummaryPdf({
    required AssessmentPdfTranslate translate,
    required LocalCampaign campaign,
    required IrnReferential referential,
    required IrnScoreSummary globalSummary,
    IrnSystemMaturitySummary? maturitySummary,
    required Map<IrnPillar, IrnScoreSummary> pillarSummaries,
    required Map<CriterionScope, IrnScoreSummary> scopeSummaries,
    required List<MapEntry<IrnPillar, IrnScoreSummary>> strongestPillars,
    required List<MapEntry<IrnPillar, IrnScoreSummary>> weakestPillars,
    DateTime? generatedAt,
  }) async {
    final generatedAtUtc = (generatedAt ?? DateTime.now()).toUtc();
    final document = pw.Document(
      title: translate(
        'screen.summary.title_prefix',
        values: {'campaign': _clean(campaign.name)},
      ),
      author: 'OpenIRN',
      subject: translate('pdf.summary.subject'),
      creator: 'OpenIRN',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            _clean(
              translate(
                'pdf.summary.page',
                values: {
                  'current': context.pageNumber,
                  'total': context.pagesCount,
                },
              ),
            ),
            style: _smallTextStyle.copyWith(color: _mutedColor),
          ),
        ),
        build: (context) => [
          _documentHeader(campaign, referential, generatedAtUtc, translate),
          pw.SizedBox(height: 14),
          _globalSummaryBlock(globalSummary, maturitySummary, translate),
          pw.SizedBox(height: 14),
          _sectionTitle(translate('screen.summary.indicators')),
          pw.SizedBox(height: 6),
          _pillarSummaryTable(pillarSummaries, translate),
          pw.SizedBox(height: 14),
          _sectionTitle(translate('pdf.summary.radar_table')),
          pw.SizedBox(height: 6),
          _radarLikeTable(pillarSummaries, translate),
          pw.SizedBox(height: 14),
          _sectionTitle(translate('screen.summary.by_scope')),
          pw.SizedBox(height: 6),
          _scopeSummaryTable(scopeSummaries, translate),
          pw.SizedBox(height: 14),
          _twoColumnRankedBlocks(strongestPillars, weakestPillars, translate),
          pw.SizedBox(height: 14),
          _methodNote(referential, translate),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _documentHeader(
    LocalCampaign campaign,
    IrnReferential referential,
    DateTime generatedAtUtc,
    AssessmentPdfTranslate translate,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(translate('screen.assessment.summary'), style: _titleStyle),
          pw.SizedBox(height: 4),
          pw.Text(_clean(campaign.name), style: _subtitleStyle),
          if (campaign.description.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(_clean(campaign.description), style: _bodyStyle),
          ],
          pw.SizedBox(height: 10),
          _keyValue(
            translate('about.referential_used'),
            '${referential.id} - ${referential.version}',
          ),
          _keyValue(
            translate('pdf.summary.campaign_status'),
            translate('campaign.status.${campaign.status.jsonValue}'),
          ),
          _keyValue(
            translate('pdf.summary.generated_at'),
            '${generatedAtUtc.toIso8601String()} UTC',
          ),
        ],
      ),
    );
  }

  pw.Widget _globalSummaryBlock(
    IrnScoreSummary summary,
    IrnSystemMaturitySummary? maturitySummary,
    AssessmentPdfTranslate translate,
  ) {
    final maturity = maturitySummary;
    final scoreLabel =
        maturity?.formattedMaturityScore ?? summary.formattedOpenIrnRnrScore;
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            translate('screen.summary.global_score'),
            style: _sectionStyle,
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _metricBox(
                maturity == null
                    ? translate('assessment.score.title')
                    : translate('screen.summary.si_maturity'),
                scoreLabel,
              ),
              pw.SizedBox(width: 8),
              _metricBox(
                translate('pdf.summary.column.completion'),
                '${(summary.completionRate * 100).toStringAsFixed(0)} %',
              ),
              pw.SizedBox(width: 8),
              _metricBox(
                translate('pdf.summary.column.answered'),
                '${summary.answeredCriteria}/${summary.totalCriteria}',
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(
                translate(
                  'assessment.score.not_concerned',
                  values: {'count': summary.notConcernedCriteria},
                ),
              ),
              _chip(
                translate(
                  'assessment.score.non_resilient',
                  values: {'count': summary.nonResilientCriteria},
                ),
              ),
              _chip(
                translate(
                  'assessment.score.intention',
                  values: {'count': summary.intentionCriteria},
                ),
              ),
              _chip(
                translate(
                  'assessment.score.medium',
                  values: {'count': summary.mediumCriteria},
                ),
              ),
              _chip(
                translate(
                  'assessment.score.result',
                  values: {'count': summary.resultCriteria},
                ),
              ),
              _chip(
                translate(
                  'assessment.score.not_answered',
                  values: {'count': summary.notAnsweredCriteria},
                ),
              ),
              if (maturity != null)
                _chip(
                  translate(
                    'assessment.score.scored_assets',
                    values: {
                      'scored': maturity.scoredAssetCount,
                      'total': maturity.totalAssetCount,
                    },
                  ),
                ),
              if (maturity != null)
                _chip(
                  translate(
                    'assessment.score.criticality_weight',
                    values: {'weight': maturity.maturityWeightTotal},
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pillarSummaryTable(
    Map<IrnPillar, IrnScoreSummary> summaries,
    AssessmentPdfTranslate translate,
  ) {
    final rows = summaries.entries
        .map(
          (entry) => <String>[
            entry.key.code,
            _clean(entry.key.label),
            entry.value.formattedOpenIrnRnrScore,
            '${entry.value.notConcernedCriteria}',
            '${entry.value.nonResilientCriteria}',
            '${entry.value.intentionCriteria}',
            '${entry.value.mediumCriteria}',
            '${entry.value.resultCriteria}',
            '${entry.value.answeredCriteria}/${entry.value.totalCriteria}',
            '${(entry.value.completionRate * 100).toStringAsFixed(0)} %',
          ],
        )
        .toList(growable: false);

    return _table(
      headers: [
        translate('pdf.summary.column.code'),
        translate('pdf.summary.column.pillar'),
        translate('pdf.summary.column.score'),
        'NC',
        'NR',
        translate('pdf.summary.column.intention'),
        translate('pdf.summary.column.medium'),
        translate('pdf.summary.column.result'),
        translate('pdf.summary.column.answered'),
        translate('pdf.summary.column.completion'),
      ],
      rows: rows,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(52),
        1: pw.FlexColumnWidth(2.7),
        2: pw.FixedColumnWidth(56),
        3: pw.FixedColumnWidth(28),
        4: pw.FixedColumnWidth(28),
        5: pw.FixedColumnWidth(28),
        6: pw.FixedColumnWidth(28),
        7: pw.FixedColumnWidth(28),
        8: pw.FixedColumnWidth(52),
        9: pw.FixedColumnWidth(70),
      },
    );
  }

  pw.Widget _radarLikeTable(
    Map<IrnPillar, IrnScoreSummary> summaries,
    AssessmentPdfTranslate translate,
  ) {
    final rows = summaries.entries
        .map(
          (entry) => <String>[
            entry.key.code,
            _clean(entry.key.label),
            entry.value.formattedOpenIrnRnrScore,
            _riskLevel(entry.value.openIrnRnrScore, translate),
            '${(entry.value.completionRate * 100).toStringAsFixed(0)} %',
          ],
        )
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          translate('pdf.summary.radar_help'),
          style: _smallTextStyle.copyWith(color: _mutedColor),
        ),
        pw.SizedBox(height: 6),
        _table(
          headers: [
            translate('pdf.summary.column.code'),
            translate('pdf.summary.column.pillar'),
            translate('pdf.summary.column.score'),
            translate('pdf.summary.column.level'),
            translate('pdf.summary.column.completion'),
          ],
          rows: rows,
          columnWidths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(52),
            1: pw.FlexColumnWidth(2.8),
            2: pw.FixedColumnWidth(58),
            3: pw.FixedColumnWidth(72),
            4: pw.FixedColumnWidth(76),
          },
        ),
      ],
    );
  }

  pw.Widget _scopeSummaryTable(
    Map<CriterionScope, IrnScoreSummary> summaries,
    AssessmentPdfTranslate translate,
  ) {
    final rows = summaries.entries
        .map(
          (entry) => <String>[
            translate('assessment.criterion.scope.${entry.key.jsonValue}'),
            entry.value.formattedOpenIrnRnrScore,
            '${entry.value.notConcernedCriteria}',
            '${entry.value.nonResilientCriteria}',
            '${entry.value.intentionCriteria}',
            '${entry.value.mediumCriteria}',
            '${entry.value.resultCriteria}',
            '${entry.value.answeredCriteria}/${entry.value.totalCriteria}',
            '${(entry.value.completionRate * 100).toStringAsFixed(0)} %',
          ],
        )
        .toList(growable: false);

    return _table(
      headers: [
        translate('pdf.summary.column.scope'),
        translate('pdf.summary.column.score'),
        'NC',
        'NR',
        translate('pdf.summary.column.intention'),
        translate('pdf.summary.column.medium'),
        translate('pdf.summary.column.result'),
        translate('pdf.summary.column.answered'),
        translate('pdf.summary.column.completion'),
      ],
      rows: rows,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(2),
        1: pw.FixedColumnWidth(56),
        2: pw.FixedColumnWidth(28),
        3: pw.FixedColumnWidth(28),
        4: pw.FixedColumnWidth(28),
        5: pw.FixedColumnWidth(28),
        6: pw.FixedColumnWidth(28),
        7: pw.FixedColumnWidth(52),
        8: pw.FixedColumnWidth(70),
      },
    );
  }

  pw.Widget _twoColumnRankedBlocks(
    List<MapEntry<IrnPillar, IrnScoreSummary>> strongestPillars,
    List<MapEntry<IrnPillar, IrnScoreSummary>> weakestPillars,
    AssessmentPdfTranslate translate,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _rankedBlock(
            translate('screen.summary.strengths'),
            strongestPillars,
            translate('pdf.summary.not_enough_scored'),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _rankedBlock(
            translate('screen.summary.attention'),
            weakestPillars,
            translate('pdf.summary.not_enough_scored'),
          ),
        ),
      ],
    );
  }

  pw.Widget _rankedBlock(
    String title,
    List<MapEntry<IrnPillar, IrnScoreSummary>> entries,
    String emptyMessage,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_clean(title), style: _labelStyle),
          pw.SizedBox(height: 6),
          if (entries.isEmpty)
            pw.Text(_clean(emptyMessage), style: _smallTextStyle)
          else
            for (final entry in entries)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  '${entry.key.code} - ${_clean(entry.key.label)} : ${entry.value.formattedOpenIrnRnrScore}',
                  style: _smallTextStyle,
                ),
              ),
        ],
      ),
    );
  }

  pw.Widget _methodNote(
    IrnReferential referential,
    AssessmentPdfTranslate translate,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(translate('pdf.summary.method_title'), style: _labelStyle),
          pw.SizedBox(height: 4),
          pw.Text(translate('pdf.summary.method_body'), style: _smallTextStyle),
          if (referential.scoring.disclaimer.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              _clean(referential.scoring.disclaimer),
              style: _smallTextStyle,
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _metricBox(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _lightPanelColor,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _borderColor),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _clean(label),
              style: _smallTextStyle.copyWith(color: _mutedColor),
            ),
            pw.SizedBox(height: 4),
            pw.Text(_clean(value), style: _metricStyle),
          ],
        ),
      ),
    );
  }

  pw.Widget _chip(String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _lightPanelColor,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Text(_clean(value), style: _smallTextStyle),
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      columnWidths: columnWidths,
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _headerColor),
          children: headers
              .map((header) => _tableCell(header, header: true))
              .toList(),
        ),
        for (final row in rows)
          pw.TableRow(children: row.map((cell) => _tableCell(cell)).toList()),
      ],
    );
  }

  pw.Widget _tableCell(String value, {bool header = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        _clean(value),
        style: header ? _tableHeaderStyle : _tableTextStyle,
      ),
    );
  }

  pw.Widget _keyValue(String key, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 92,
            child: pw.Text(_clean(key), style: _labelStyle),
          ),
          pw.Expanded(child: pw.Text(_clean(value), style: _bodyStyle)),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Text(_clean(title), style: _sectionStyle);
  }

  String _riskLevel(double? score, AssessmentPdfTranslate translate) {
    if (score == null) {
      return translate('screen.summary.not_scored');
    }
    if (score >= 80) {
      return translate('screen.summary.risk.low');
    }
    if (score >= 60) {
      return translate('screen.summary.risk.moderate');
    }
    if (score >= 40) {
      return translate('screen.summary.risk.high');
    }
    return translate('screen.summary.risk.critical');
  }

  String _clean(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2022', '-')
        .replaceAll('\u0153', 'oe')
        .replaceAll('\u0152', 'OE');
  }
}

const _borderColor = PdfColor(0.84, 0.87, 0.91);
const _headerColor = PdfColor(0.91, 0.94, 0.97);
const _lightPanelColor = PdfColor(0.96, 0.97, 0.98);
const _mutedColor = PdfColor(0.38, 0.43, 0.50);

final _panelDecoration = pw.BoxDecoration(
  border: pw.Border.all(color: _borderColor, width: 0.6),
  borderRadius: pw.BorderRadius.circular(10),
);

final _titleStyle = pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold);
final _subtitleStyle = pw.TextStyle(
  fontSize: 13,
  fontWeight: pw.FontWeight.bold,
);
final _sectionStyle = pw.TextStyle(
  fontSize: 14,
  fontWeight: pw.FontWeight.bold,
);
final _metricStyle = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
final _labelStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
const _bodyStyle = pw.TextStyle(fontSize: 10);
const _smallTextStyle = pw.TextStyle(fontSize: 8.5);
final _tableHeaderStyle = pw.TextStyle(
  fontSize: 8,
  fontWeight: pw.FontWeight.bold,
);
const _tableTextStyle = pw.TextStyle(fontSize: 8);
