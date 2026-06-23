import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/irn_referential.dart';
import '../../domain/repositories/irn_referential_repository.dart';

class AssetIrnReferentialRepository implements IrnReferentialRepository {
  final String manifestAssetPath;

  const AssetIrnReferentialRepository({
    this.manifestAssetPath = 'assets/referentials/manifest.json',
  });

  @override
  Future<IrnReferential> getActiveReferential() async {
    final manifestRaw = await rootBundle.loadString(manifestAssetPath);
    final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
    final activeReferentialId = manifest['activeReferentialId'] as String?;
    final referentials =
        (manifest['referentials'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);

    if (referentials.isEmpty) {
      throw StateError('Aucun référentiel déclaré dans $manifestAssetPath');
    }

    final selected = referentials.firstWhere(
      (item) =>
          activeReferentialId == null || item['id'] == activeReferentialId,
      orElse: () => referentials.first,
    );

    final assetPath = selected['assetPath'] as String?;
    if (assetPath == null || assetPath.isEmpty) {
      throw StateError('assetPath absent dans le manifeste du référentiel');
    }

    final referentialRaw = await rootBundle.loadString(assetPath);
    final referentialJson = jsonDecode(referentialRaw) as Map<String, dynamic>;
    return IrnReferential.fromJson(referentialJson);
  }
}
