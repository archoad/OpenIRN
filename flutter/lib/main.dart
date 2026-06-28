import 'package:flutter/material.dart';

import 'data/repositories/asset_irn_referential_repository.dart';
import 'presentation/referential/referential_overview_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
          centerTitle: true,
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
      builder: (context, child) {
        return _KeyboardDismissScope(child: child ?? const SizedBox.shrink());
      },
      home: const ReferentialOverviewScreen(
        repository: AssetIrnReferentialRepository(),
      ),
    );
  }
}

class _KeyboardDismissScope extends StatelessWidget {
  final Widget child;

  const _KeyboardDismissScope({required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        final focusScope = FocusScope.of(context);
        if (!focusScope.hasPrimaryFocus && focusScope.focusedChild != null) {
          focusScope.unfocus();
        }
      },
      child: child,
    );
  }
}
