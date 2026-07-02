import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

class LocalImageFileService {
  const LocalImageFileService();

  static const XTypeGroup _pngTypeGroup = XTypeGroup(
    label: 'Image PNG',
    extensions: <String>['png'],
    mimeTypes: <String>['image/png'],
    uniformTypeIdentifiers: <String>['public.png'],
  );

  Future<String?> savePng({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    final fileName = _ensurePngExtension(suggestedName);
    debugPrint('[OpenIRN] Opening save dialog for $fileName');

    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[_pngTypeGroup],
      confirmButtonText: 'Enregistrer',
    );
    if (location == null) {
      debugPrint('[OpenIRN] Save dialog cancelled');
      return null;
    }

    final path = _ensurePngExtension(location.path);
    debugPrint('[OpenIRN] Saving PNG export to $path');

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await File(path).writeAsBytes(bytes, flush: true);
    } else {
      final file = XFile.fromData(bytes, name: fileName, mimeType: 'image/png');
      await file.saveTo(path);
    }

    return path;
  }

  String buildExportFileName({
    required String campaignName,
    required String label,
    DateTime? now,
  }) {
    final timestamp = _compactTimestamp((now ?? DateTime.now()).toLocal());
    final safeCampaignName = _safeFilePart(campaignName, fallback: 'campagne');
    final safeLabel = _safeFilePart(label, fallback: 'export');
    return 'openirn_${safeCampaignName}_${safeLabel}_$timestamp.png';
  }

  String _ensurePngExtension(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.png')) {
      return trimmed;
    }
    return '$trimmed.png';
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
