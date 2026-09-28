import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openirn/main.dart';

void main() {
  testWidgets('uses the compact hierarchical OpenIRN typography scale', (
    tester,
  ) async {
    late TextTheme textTheme;

    await tester.pumpWidget(
      OpenIrnApp(
        home: Builder(
          builder: (context) {
            textTheme = Theme.of(context).textTheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(textTheme.displayLarge?.fontSize, 28);
    expect(textTheme.displayMedium?.fontSize, 24);
    expect(textTheme.displaySmall?.fontSize, 22);
    expect(textTheme.headlineLarge?.fontSize, 22);
    expect(textTheme.headlineMedium?.fontSize, 20);
    expect(textTheme.headlineSmall?.fontSize, 18);
    expect(textTheme.titleLarge?.fontSize, 18);
    expect(textTheme.titleMedium?.fontSize, 14);
    expect(textTheme.titleSmall?.fontSize, 13);
    expect(textTheme.bodyLarge?.fontSize, 14);
    expect(textTheme.bodyMedium?.fontSize, 13);
    expect(textTheme.bodySmall?.fontSize, 12);
    expect(textTheme.labelLarge?.fontSize, 12);
    expect(textTheme.labelMedium?.fontSize, 11);
    expect(textTheme.labelSmall?.fontSize, 10);
    for (final style in <TextStyle?>[
      textTheme.displayLarge,
      textTheme.displayMedium,
      textTheme.displaySmall,
      textTheme.headlineLarge,
      textTheme.headlineMedium,
      textTheme.headlineSmall,
      textTheme.titleLarge,
      textTheme.titleMedium,
      textTheme.titleSmall,
      textTheme.bodyLarge,
      textTheme.bodyMedium,
      textTheme.bodySmall,
      textTheme.labelLarge,
      textTheme.labelMedium,
      textTheme.labelSmall,
    ]) {
      expect(style?.fontFamily, 'Inter');
    }
  });

  testWidgets('honors 200 percent platform text scaling', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    late TextTheme textTheme;
    late TextScaler textScaler;

    await tester.pumpWidget(
      OpenIrnApp(
        home: Builder(
          builder: (context) {
            textTheme = Theme.of(context).textTheme;
            textScaler = MediaQuery.textScalerOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(textScaler.scale(textTheme.headlineLarge!.fontSize!), 44);
    expect(textScaler.scale(textTheme.bodyMedium!.fontSize!), 26);
    expect(textScaler.scale(textTheme.labelSmall!.fontSize!), 20);
  });
}
