import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inventory relationship diagram is bundled as a compact WebP', () {
    const assetPath = 'assets/images/openirn_graph.webp';
    final asset = File(assetPath);
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(asset.existsSync(), isTrue);
    expect(asset.lengthSync(), lessThan(100 * 1024));
    final header = asset.readAsBytesSync().take(12).toList(growable: false);
    expect(String.fromCharCodes(header.take(4)), 'RIFF');
    expect(String.fromCharCodes(header.skip(8)), 'WEBP');
    expect(pubspec, contains('- $assetPath'));
  });
}
