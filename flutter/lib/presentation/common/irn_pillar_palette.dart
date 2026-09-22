import 'package:flutter/material.dart';

import '../../domain/models/irn_referential.dart';

class IrnPillarVisualStyle {
  final Color borderColor;
  final Color backgroundColor;
  final Color foregroundColor;

  const IrnPillarVisualStyle({
    required this.borderColor,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  RoundedRectangleBorder cardShape({double borderRadius = 16}) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: BorderSide(color: borderColor, width: 1.5),
    );
  }

  BoxDecoration boxDecoration({double borderRadius = 12}) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 1.5),
    );
  }
}

abstract final class IrnPillarPalette {
  static const List<Color> borderColors = <Color>[
    Color(0xFF715660),
    Color(0xFF846470),
    Color(0xFF566071),
    Color(0xFF727F96),
    Color(0xFFC39F72),
    Color(0xFFD5BF95),
    Color(0xFF667762),
    Color(0xFF879E82),
  ];

  static const Color _darkText = Color(0xFF1F2937);
  static const Color _lightText = Colors.white;
  static const double _pastelOpacity = 0.20;

  static IrnPillarVisualStyle forPillar(IrnPillar pillar) {
    return forCode(pillar.code);
  }

  static IrnPillarVisualStyle forCode(String code) {
    final borderColor = borderColors[_indexForCode(code)];
    final backgroundColor = Color.alphaBlend(
      borderColor.withValues(alpha: _pastelOpacity),
      Colors.white,
    );
    return IrnPillarVisualStyle(
      borderColor: borderColor,
      backgroundColor: backgroundColor,
      foregroundColor: readableForeground(backgroundColor),
    );
  }

  static Color readableForeground(Color backgroundColor) {
    final darkContrast = contrastRatio(_darkText, backgroundColor);
    final lightContrast = contrastRatio(_lightText, backgroundColor);
    return darkContrast >= lightContrast ? _darkText : _lightText;
  }

  static double contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = firstLuminance >= secondLuminance
        ? firstLuminance
        : secondLuminance;
    final darker = firstLuminance >= secondLuminance
        ? secondLuminance
        : firstLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static int _indexForCode(String code) {
    final match = RegExp(r'(\d+)(?!.*\d)').firstMatch(code.trim());
    final pillarNumber = int.tryParse(match?.group(1) ?? '');
    if (pillarNumber != null &&
        pillarNumber >= 1 &&
        pillarNumber <= borderColors.length) {
      return pillarNumber - 1;
    }
    return 0;
  }
}
