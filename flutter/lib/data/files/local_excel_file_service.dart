import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

class LocalExcelFile {
  final String name;
  final Uint8List bytes;

  const LocalExcelFile({required this.name, required this.bytes});
}

class LocalExcelFileService {
  const LocalExcelFileService();

  static const XTypeGroup _excelTypeGroup = XTypeGroup(
    label: 'Excel',
    extensions: <String>['xlsx'],
    mimeTypes: <String>[
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ],
    uniformTypeIdentifiers: <String>['org.openxmlformats.spreadsheetml.sheet'],
  );

  Future<String?> saveExcel({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    final fileName = _ensureExcelExtension(suggestedName);
    debugPrint('[OpenIRN] Opening Excel save dialog for $fileName');

    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[_excelTypeGroup],
      confirmButtonText: 'Enregistrer',
    );
    if (location == null) {
      debugPrint('[OpenIRN] Excel save dialog cancelled');
      return null;
    }

    final path = _ensureExcelExtension(location.path);
    debugPrint('[OpenIRN] Saving Excel inventory export to $path');

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await File(path).writeAsBytes(bytes, flush: true);
    } else {
      final file = XFile.fromData(
        bytes,
        name: fileName,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await file.saveTo(path);
    }

    return path;
  }

  Future<LocalExcelFile?> pickExcel() async {
    debugPrint('[OpenIRN] Opening Excel file picker');
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_excelTypeGroup],
      confirmButtonText: 'Importer',
    );
    if (file == null) {
      debugPrint('[OpenIRN] Excel open dialog cancelled');
      return null;
    }

    debugPrint('[OpenIRN] Reading Excel file ${file.name}');
    return LocalExcelFile(name: file.name, bytes: await file.readAsBytes());
  }

  String _ensureExcelExtension(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.xlsx')) {
      return trimmed;
    }
    return '$trimmed.xlsx';
  }
}
