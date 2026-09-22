import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/presentation/common/irn_pillar_palette.dart';

void main() {
  const expectedColors = <Color>[
    Color(0xFF715660),
    Color(0xFF846470),
    Color(0xFF566071),
    Color(0xFF727F96),
    Color(0xFFC39F72),
    Color(0xFFD5BF95),
    Color(0xFF667762),
    Color(0xFF879E82),
  ];

  test('maps RES-1 through RES-8 to the requested palette', () {
    for (var index = 0; index < expectedColors.length; index += 1) {
      final style = IrnPillarPalette.forCode('RES-${index + 1}');
      expect(style.borderColor, expectedColors[index]);
    }
  });

  test('builds a pastel background with readable text for every pillar', () {
    for (var index = 0; index < expectedColors.length; index += 1) {
      final style = IrnPillarPalette.forCode('RES-${index + 1}');
      expect(style.backgroundColor, isNot(style.borderColor));
      expect(
        IrnPillarPalette.contrastRatio(
          style.foregroundColor,
          style.backgroundColor,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
