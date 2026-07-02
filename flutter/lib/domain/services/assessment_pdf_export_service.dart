import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/irn_assessment.dart';
import '../models/irn_referential.dart';
import '../models/local_campaign.dart';

class AssessmentPdfExportService {
  const AssessmentPdfExportService();

  Future<Uint8List> buildSummaryPdf({
    required LocalCampaign campaign,
    required IrnReferential referential,
    required IrnScoreSummary globalSummary,
    required Map<IrnPillar, IrnScoreSummary> pillarSummaries,
    required Map<CriterionScope, IrnScoreSummary> scopeSummaries,
    required List<MapEntry<IrnPillar, IrnScoreSummary>> strongestPillars,
    required List<MapEntry<IrnPillar, IrnScoreSummary>> weakestPillars,
    DateTime? generatedAt,
  }) async {
    final generatedAtUtc = (generatedAt ?? DateTime.now()).toUtc();
    final document = pw.Document(
      title: 'OpenIRN - Synthese IRN - ${_clean(campaign.name)}',
      author: 'OpenIRN',
      subject: 'Synthese de campagne IRN',
      creator: 'OpenIRN',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'OpenIRN - page ${context.pageNumber}/${context.pagesCount}',
            style: _smallTextStyle.copyWith(color: _mutedColor),
          ),
        ),
        build: (context) => [
          _documentHeader(campaign, referential, generatedAtUtc),
          pw.SizedBox(height: 14),
          _globalSummaryBlock(globalSummary),
          pw.SizedBox(height: 14),
          _sectionTitle('Indicateurs IRN'),
          pw.SizedBox(height: 6),
          _pillarSummaryTable(pillarSummaries),
          pw.SizedBox(height: 14),
          _sectionTitle('Radar IRN - lecture tabulaire'),
          pw.SizedBox(height: 6),
          _radarLikeTable(pillarSummaries),
          pw.SizedBox(height: 14),
          _sectionTitle('Repartition par portee'),
          pw.SizedBox(height: 6),
          _scopeSummaryTable(scopeSummaries),
          pw.SizedBox(height: 14),
          _twoColumnRankedBlocks(strongestPillars, weakestPillars),
          pw.SizedBox(height: 14),
          _methodNote(referential),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _documentHeader(
    LocalCampaign campaign,
    IrnReferential referential,
    DateTime generatedAtUtc,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Synthese IRN', style: _titleStyle),
          pw.SizedBox(height: 4),
          pw.Text(_clean(campaign.name), style: _subtitleStyle),
          if (campaign.description.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(_clean(campaign.description), style: _bodyStyle),
          ],
          pw.SizedBox(height: 10),
          _keyValue(
            'Referentiel',
            '${referential.id} - ${referential.version}',
          ),
          _keyValue('Statut campagne', campaign.status.label),
          _keyValue('Genere le', '${generatedAtUtc.toIso8601String()} UTC'),
        ],
      ),
    );
  }

  pw.Widget _globalSummaryBlock(IrnScoreSummary summary) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Score global', style: _sectionStyle),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _metricBox('Score IRN', summary.formattedOpenIrnRnrScore),
              pw.SizedBox(width: 8),
              _metricBox(
                'Completude',
                '${(summary.completionRate * 100).toStringAsFixed(0)} %',
              ),
              pw.SizedBox(width: 8),
              _metricBox(
                'Criteres cotes',
                '${summary.answeredCriteria}/${summary.totalCriteria}',
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('R : ${summary.resilientCriteria}'),
              _chip('NR : ${summary.nonResilientCriteria}'),
              _chip('N.C. : ${summary.notAnsweredCriteria}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pillarSummaryTable(Map<IrnPillar, IrnScoreSummary> summaries) {
    final rows = summaries.entries
        .map(
          (entry) => <String>[
            entry.key.code,
            _clean(entry.key.label),
            entry.value.formattedOpenIrnRnrScore,
            '${entry.value.resilientCriteria}',
            '${entry.value.nonResilientCriteria}',
            '${entry.value.answeredCriteria}/${entry.value.totalCriteria}',
            '${(entry.value.completionRate * 100).toStringAsFixed(0)} %',
          ],
        )
        .toList(growable: false);

    return _table(
      headers: const [
        'Code',
        'Pilier',
        'Score',
        'R',
        'NR',
        'Cotes',
        'Completude',
      ],
      rows: rows,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(52),
        1: pw.FlexColumnWidth(2.7),
        2: pw.FixedColumnWidth(56),
        3: pw.FixedColumnWidth(32),
        4: pw.FixedColumnWidth(32),
        5: pw.FixedColumnWidth(52),
        6: pw.FixedColumnWidth(70),
      },
    );
  }

  pw.Widget _radarLikeTable(Map<IrnPillar, IrnScoreSummary> summaries) {
    final rows = summaries.entries
        .map(
          (entry) => <String>[
            entry.key.code,
            _clean(entry.key.label),
            entry.value.formattedOpenIrnRnrScore,
            _riskLevel(entry.value.openIrnRnrScore),
            '${(entry.value.completionRate * 100).toStringAsFixed(0)} %',
          ],
        )
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Lecture tabulaire du radar, sans rendu vectoriel complexe, pour garantir un PDF lisible sur tous les lecteurs.',
          style: _smallTextStyle.copyWith(color: _mutedColor),
        ),
        pw.SizedBox(height: 6),
        _table(
          headers: const ['Code', 'Pilier', 'Score', 'Niveau', 'Completude'],
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

  pw.Widget _scopeSummaryTable(Map<CriterionScope, IrnScoreSummary> summaries) {
    final rows = summaries.entries
        .map(
          (entry) => <String>[
            _clean(entry.key.label),
            entry.value.formattedOpenIrnRnrScore,
            '${entry.value.resilientCriteria}',
            '${entry.value.nonResilientCriteria}',
            '${entry.value.answeredCriteria}/${entry.value.totalCriteria}',
            '${(entry.value.completionRate * 100).toStringAsFixed(0)} %',
          ],
        )
        .toList(growable: false);

    return _table(
      headers: const ['Portee', 'Score', 'R', 'NR', 'Cotes', 'Completude'],
      rows: rows,
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(2),
        1: pw.FixedColumnWidth(60),
        2: pw.FixedColumnWidth(36),
        3: pw.FixedColumnWidth(36),
        4: pw.FixedColumnWidth(58),
        5: pw.FixedColumnWidth(76),
      },
    );
  }

  pw.Widget _twoColumnRankedBlocks(
    List<MapEntry<IrnPillar, IrnScoreSummary>> strongestPillars,
    List<MapEntry<IrnPillar, IrnScoreSummary>> weakestPillars,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _rankedBlock(
            'Points forts provisoires',
            strongestPillars,
            'Pas encore assez de criteres cotes.',
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _rankedBlock(
            'Points d attention provisoires',
            weakestPillars,
            'Pas encore assez de criteres cotes.',
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

  pw.Widget _methodNote(IrnReferential referential) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: _panelDecoration,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Note methodologique', style: _labelStyle),
          pw.SizedBox(height: 4),
          pw.Text(
            'Score OpenIRN R/NR non pondere. Les criteres non cotes sont exclus du score et restent inclus dans la completude.',
            style: _smallTextStyle,
          ),
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

  String _riskLevel(double? score) {
    if (score == null) {
      return 'Non cote';
    }
    if (score >= 80) {
      return 'Faible';
    }
    if (score >= 60) {
      return 'Modere';
    }
    if (score >= 40) {
      return 'Haut';
    }
    return 'Critique';
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
