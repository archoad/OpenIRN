import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/presentation/common/irn_pillar_palette.dart';

void main() {
  const expectedColors = <Color>[
    Color(0xFF1E40AF),
    Color(0xFFA16207),
    Color(0xFF7E22CE),
    Color(0xFFC2410C),
    Color(0xFF0F766E),
    Color(0xFF0369A1),
    Color(0xFFBE123C),
    Color(0xFF2F7D32),
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
      expect(
        IrnPillarPalette.contrastRatio(
          style.borderColor,
          style.backgroundColor,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(
        IrnPillarPalette.contrastRatio(Colors.white, style.borderColor),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
