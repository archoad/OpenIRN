import 'dart:math' as math;

import 'package:flutter/material.dart';

class PillarRadarDatum {
  final String code;
  final String label;
  final double? score;
  final double completionRate;

  const PillarRadarDatum({
    required this.code,
    required this.label,
    required this.score,
    required this.completionRate,
  });

  double get normalizedScore => ((score ?? 0) / 100).clamp(0, 1).toDouble();

  String get formattedScore {
    final currentScore = score;
    if (currentScore == null) {
      return 'N/A';
    }
    return '${currentScore.toStringAsFixed(0)} %';
  }
}

class PillarRadarChart extends StatelessWidget {
  final List<PillarRadarDatum> data;

  const PillarRadarChart({
    required this.data,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _PillarRadarPainter(
          data: data,
          textStyle:
              theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12),
          axisColor: colorScheme.outlineVariant,
          gridColor: colorScheme.outlineVariant,
          fillColor: colorScheme.primary.withAlpha(42),
          strokeColor: colorScheme.primary,
          pointColor: colorScheme.primary,
          textColor: colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _PillarRadarPainter extends CustomPainter {
  final List<PillarRadarDatum> data;
  final TextStyle textStyle;
  final Color axisColor;
  final Color gridColor;
  final Color fillColor;
  final Color strokeColor;
  final Color pointColor;
  final Color textColor;

  const _PillarRadarPainter({
    required this.data,
    required this.textStyle,
    required this.axisColor,
    required this.gridColor,
    required this.fillColor,
    required this.strokeColor,
    required this.pointColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = data.length;
    if (count < 3) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 58;
    if (radius <= 0) {
      return;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    for (final level in const [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawPath(_polygonPath(center, radius * level, count), gridPaint);
    }

    for (var index = 0; index < count; index += 1) {
      final angle = _angleFor(index, count);
      final axisEnd = _point(center, radius, angle);
      canvas.drawLine(center, axisEnd, axisPaint);
      _drawLabel(canvas, size, center, radius + 26, angle, data[index].code);
    }

    final valuePath = Path();
    for (var index = 0; index < count; index += 1) {
      final angle = _angleFor(index, count);
      final point = _point(center, radius * data[index].normalizedScore, angle);
      if (index == 0) {
        valuePath.moveTo(point.dx, point.dy);
      } else {
        valuePath.lineTo(point.dx, point.dy);
      }
    }
    valuePath.close();

    canvas.drawPath(valuePath, fillPaint);
    canvas.drawPath(valuePath, strokePaint);

    for (var index = 0; index < count; index += 1) {
      final angle = _angleFor(index, count);
      final point = _point(center, radius * data[index].normalizedScore, angle);
      canvas.drawCircle(point, 4, pointPaint);
    }

    _drawCenterLabel(canvas, center, 'IRN');
  }

  Path _polygonPath(Offset center, double radius, int count) {
    final path = Path();
    for (var index = 0; index < count; index += 1) {
      final angle = _angleFor(index, count);
      final point = _point(center, radius, angle);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  double _angleFor(int index, int count) {
    return -math.pi / 2 + (2 * math.pi * index / count);
  }

  Offset _point(Offset center, double radius, double angle) {
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double angle,
    String text,
  ) {
    final labelStyle =
        textStyle.copyWith(color: textColor, fontWeight: FontWeight.w600);
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final anchor = _point(center, radius, angle);
    final dx = (anchor.dx - textPainter.width / 2)
        .clamp(0.0, size.width - textPainter.width);
    final dy = (anchor.dy - textPainter.height / 2)
        .clamp(0.0, size.height - textPainter.height);
    textPainter.paint(canvas, Offset(dx, dy));
  }

  void _drawCenterLabel(Canvas canvas, Offset center, String text) {
    final labelStyle = textStyle.copyWith(color: textColor.withAlpha(180));
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PillarRadarPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.textColor != textColor;
  }
}
