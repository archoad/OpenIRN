import 'dart:math' as math;

import 'package:flutter/material.dart';

EdgeInsets responsiveDialogInsetPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) {
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  }
  if (width < 900) {
    return const EdgeInsets.symmetric(horizontal: 28, vertical: 24);
  }
  return const EdgeInsets.symmetric(horizontal: 48, vertical: 32);
}

double responsiveDialogWidth(
  BuildContext context, {
  double maxWidth = 720,
  double minWidth = 320,
}) {
  final size = MediaQuery.sizeOf(context);
  final insetPadding = responsiveDialogInsetPadding(context);
  final availableWidth = math.max(280.0, size.width - insetPadding.horizontal);
  final effectiveMaxWidth = math.min(maxWidth, availableWidth);

  if (effectiveMaxWidth <= minWidth) {
    return effectiveMaxWidth;
  }

  final screenWidth = size.width;
  double targetWidth;
  if (screenWidth >= 1200) {
    targetWidth = screenWidth * 0.62;
  } else if (screenWidth >= 900) {
    targetWidth = screenWidth * 0.72;
  } else if (screenWidth >= 600) {
    targetWidth = screenWidth * 0.86;
  } else {
    targetWidth = availableWidth;
  }

  return targetWidth.clamp(minWidth, effectiveMaxWidth).toDouble();
}

double responsiveDialogMaxHeight(
  BuildContext context, {
  double heightFactor = 0.82,
}) {
  final size = MediaQuery.sizeOf(context);
  final insetPadding = responsiveDialogInsetPadding(context);
  final availableHeight = math.max(220.0, size.height - insetPadding.vertical);
  return math.min(availableHeight, size.height * heightFactor);
}

bool isResponsiveDialogCompact(
  BuildContext context, {
  double maxWidth = 720,
  double breakpoint = 680,
}) {
  return responsiveDialogWidth(context, maxWidth: maxWidth) < breakpoint;
}

class ResponsiveDialogContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double minWidth;

  const ResponsiveDialogContent({
    required this.child,
    this.maxWidth = 720,
    this.minWidth = 320,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: responsiveDialogWidth(
        context,
        maxWidth: maxWidth,
        minWidth: minWidth,
      ),
      child: child,
    );
  }
}
