import 'package:flutter/material.dart';

import 'data/repositories/api_irn_referential_repository.dart';
import 'data/repositories/legacy_local_storage_purge_service.dart';
import 'domain/services/app_session_manager.dart';
import 'domain/services/app_sync_coordinator.dart';
import 'presentation/referential/referential_overview_screen.dart';

final GlobalKey<NavigatorState> openIrnNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const LegacyLocalStoragePurgeService().purge();
  runApp(const OpenIrnApp());
}

class OpenIrnApp extends StatelessWidget {
  const OpenIrnApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

    return MaterialApp(
      navigatorKey: openIrnNavigatorKey,
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
        return _SessionActivityScope(child: child ?? const SizedBox.shrink());
      },
      home: const ReferentialOverviewScreen(
        repository: ApiIrnReferentialRepository(),
      ),
    );
  }
}

class _SessionActivityScope extends StatefulWidget {
  final Widget child;

  const _SessionActivityScope({required this.child});

  @override
  State<_SessionActivityScope> createState() => _SessionActivityScopeState();
}

class _SessionActivityScopeState extends State<_SessionActivityScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSessionManager.instance.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    AppSessionManager.instance.removeListener(_handleSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppSessionManager.instance.validateSession();
      AppSessionManager.instance.registerActivity();
    }
  }

  void _handleSessionChanged() {
    if (AppSessionManager.instance.hasActiveSession) {
      return;
    }

    AppSyncCoordinator.instance.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openIrnNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
  }

  void _recordUserActivity() {
    AppSessionManager.instance.registerActivity();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _recordUserActivity();
        final focusScope = FocusScope.of(context);
        if (!focusScope.hasPrimaryFocus && focusScope.focusedChild != null) {
          focusScope.unfocus();
        }
      },
      onPointerSignal: (_) => _recordUserActivity(),
      child: widget.child,
    );
  }
}
