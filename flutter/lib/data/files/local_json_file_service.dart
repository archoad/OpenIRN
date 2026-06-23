import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

class LocalJsonFile {
  final String name;
  final String content;

  const LocalJsonFile({
    required this.name,
    required this.content,
  });
}

class LocalJsonFileService {
  const LocalJsonFileService();

  static const XTypeGroup _jsonTypeGroup = XTypeGroup(
    label: 'JSON',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
    uniformTypeIdentifiers: <String>['public.json'],
  );

  Future<String?> saveJson({
    required String content,
    required String suggestedName,
  }) async {
    final fileName = _ensureJsonExtension(suggestedName);
    debugPrint('[OpenIRN] Opening save dialog for $fileName');

    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[_jsonTypeGroup],
      confirmButtonText: 'Enregistrer',
    );
    if (location == null) {
      debugPrint('[OpenIRN] Save dialog cancelled');
      return null;
    }

    final path = _ensureJsonExtension(location.path);
    debugPrint('[OpenIRN] Saving JSON export to $path');

    // On desktop, using dart:io is more transparent and surfaces filesystem
    // errors better than a silent XFile.saveTo failure. The XFile fallback is
    // kept for platforms where direct file paths are less predictable.
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await File(path).writeAsString(content, encoding: utf8, flush: true);
    } else {
      final bytes = Uint8List.fromList(utf8.encode(content));
      final file = XFile.fromData(
        bytes,
        name: fileName,
        mimeType: 'application/json',
      );
      await file.saveTo(path);
    }

    return path;
  }

  Future<LocalJsonFile?> pickJson() async {
    debugPrint('[OpenIRN] Opening JSON file picker');
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_jsonTypeGroup],
      confirmButtonText: 'Ouvrir',
    );
    if (file == null) {
      debugPrint('[OpenIRN] Open dialog cancelled');
      return null;
    }

    debugPrint('[OpenIRN] Reading JSON file ${file.name}');
    final content = await file.readAsString();
    return LocalJsonFile(
      name: file.name,
      content: content,
    );
  }

  String buildExportFileName({
    required String campaignName,
    required String referentialVersion,
    DateTime? now,
  }) {
    final timestamp = _compactTimestamp((now ?? DateTime.now()).toLocal());
    final safeCampaignName = _safeFilePart(campaignName, fallback: 'campagne');
    final safeVersion =
        _safeFilePart(referentialVersion, fallback: 'referentiel');
    return 'openirn_${safeCampaignName}_${safeVersion}_$timestamp.json';
  }

  String _ensureJsonExtension(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.json')) {
      return trimmed;
    }
    return '$trimmed.json';
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
