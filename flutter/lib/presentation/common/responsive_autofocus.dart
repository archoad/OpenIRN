import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const double _mobileAutofocusBreakpoint = 700;

bool shouldAutofocusTextField(BuildContext context) {
  final mediaQuery = MediaQuery.maybeOf(context);
  if (mediaQuery == null) {
    return false;
  }

  return mediaQuery.size.width >= _mobileAutofocusBreakpoint;
}

bool shouldUseMobileKeyboardWorkaround(BuildContext context) {
  final mediaQuery = MediaQuery.maybeOf(context);
  final shortestSide = mediaQuery?.size.shortestSide ?? 0;
  final isCompact = shortestSide < _mobileAutofocusBreakpoint;

  return isCompact && defaultTargetPlatform == TargetPlatform.iOS;
}

TextInputType safeKeyboardType(
  BuildContext context,
  TextInputType preferredKeyboardType,
) {
  if (!shouldUseMobileKeyboardWorkaround(context)) {
    return preferredKeyboardType;
  }

  if (preferredKeyboardType == TextInputType.multiline) {
    return preferredKeyboardType;
  }

  return TextInputType.text;
}
