import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

class LocalPdfFileService {
  const LocalPdfFileService();

  static const XTypeGroup _pdfTypeGroup = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
    uniformTypeIdentifiers: <String>['com.adobe.pdf'],
  );

  Future<String?> savePdf({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    final fileName = _ensurePdfExtension(suggestedName);
    debugPrint('[OpenIRN] Opening save dialog for $fileName');

    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[_pdfTypeGroup],
      confirmButtonText: 'Enregistrer',
    );
    if (location == null) {
      debugPrint('[OpenIRN] Save dialog cancelled');
      return null;
    }

    final path = _ensurePdfExtension(location.path);
    debugPrint('[OpenIRN] Saving PDF export to $path');

    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await File(path).writeAsBytes(bytes, flush: true);
    } else {
      final file = XFile.fromData(
        bytes,
        name: fileName,
        mimeType: 'application/pdf',
      );
      await file.saveTo(path);
    }

    return path;
  }

  String buildExportFileName({
    required String campaignName,
    DateTime? now,
  }) {
    final timestamp = _compactTimestamp((now ?? DateTime.now()).toLocal());
    final safeCampaignName = _safeFilePart(campaignName, fallback: 'campagne');
    return 'openirn_${safeCampaignName}_synthese_irn_$timestamp.pdf';
  }

  String _ensurePdfExtension(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.pdf')) {
      return trimmed;
    }
    return '$trimmed.pdf';
  }

  String _compactTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}';
  }

  String _safeFilePart(String value, {required String fallback}) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }
}
