import 'package:flutter/material.dart';

import 'data/repositories/asset_irn_referential_repository.dart';
import 'presentation/referential/referential_overview_screen.dart';

void main() {
  runApp(const OpenIrnApp());
}

class OpenIrnApp extends StatelessWidget {
  const OpenIrnApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

    return MaterialApp(
      title: 'OpenIRN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      home: const ReferentialOverviewScreen(
        repository: AssetIrnReferentialRepository(),
      ),
    );
  }
}
