import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/openirn_localizations.dart';
import 'sync_connectivity_indicator.dart';

/// AppBar commune OpenIRN.
///
/// Objectif UX : une barre stable et responsive sur desktop, tablette et mobile :
/// flèche retour à gauche, titre centré, menu d'actions à droite.
class OpenIrnAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<OpenIrnAppBarAction> actions;
  final bool automaticallyImplyLeading;

  const OpenIrnAppBar({
    required this.title,
    this.actions = const <OpenIrnAppBarAction>[],
    this.automaticallyImplyLeading = true,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final visibleActions = actions.where((action) => !action.hidden).toList();

    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: true,
      title: Text(
        i18n.text(title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
      actions: [
        const SyncConnectivityIndicator(),
        const SizedBox(width: 2),
        const OpenIrnLanguageSwitcher(),
        const SizedBox(width: 2),
        if (visibleActions.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: context.tr('common.actions', fallback: 'Actions'),
            icon: const Icon(Icons.more_vert),
            onSelected: (id) {
              final action = visibleActions
                  .where((candidate) => !candidate.isDivider)
                  .cast<OpenIrnAppBarAction?>()
                  .firstWhere(
                    (candidate) => candidate?.id == id,
                    orElse: () => null,
                  );
              action?.onPressed?.call();
            },
            itemBuilder: (context) {
              return visibleActions.map<PopupMenuEntry<String>>((action) {
                if (action.isDivider) {
                  return const PopupMenuDivider();
                }

                return PopupMenuItem<String>(
                  value: action.id,
                  enabled: action.enabled && action.onPressed != null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (action.icon != null) ...[
                        Icon(
                          action.icon,
                          size: 20,
                          color: action.destructive
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          context.trText(action.label),
                          overflow: TextOverflow.ellipsis,
                          style: action.destructive
                              ? TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class OpenIrnLanguageSwitcher extends StatelessWidget {
  const OpenIrnLanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return ListenableBuilder(
      listenable: i18n,
      builder: (context, _) {
        final currentLanguage = i18n.language;
        final chooseLanguageLabel = context.tr(
          'common.language.choose',
          fallback: 'Choisir la langue de l’interface',
        );
        return PopupMenuButton<OpenIrnLanguage>(
          key: ValueKey<OpenIrnLanguage>(currentLanguage),
          tooltip: chooseLanguageLabel,
          initialValue: currentLanguage,
          padding: EdgeInsets.zero,
          onSelected: (language) {
            unawaited(i18n.setLanguage(language));
          },
          itemBuilder: (context) => OpenIrnLanguage.values.map((language) {
            final selected = currentLanguage == language;
            final languageLabel = context.tr(
              'common.language.${language.code}',
              fallback: language.label,
            );
            return PopupMenuItem<OpenIrnLanguage>(
              value: language,
              child: Semantics(
                selected: selected,
                label: languageLabel,
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: OpenIrnLanguageFlag(
                        key: ValueKey<String>(
                          'openirn-language-flag-menu-${language.code}',
                        ),
                        language: language,
                        width: 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(languageLabel)),
                    if (selected) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.check, size: 20),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
          child: Semantics(
            button: true,
            label: context.tr(
              'common.language.current',
              fallback: 'Langue actuelle : {language}',
              values: {
                'language': context.tr(
                  'common.language.${currentLanguage.code}',
                  fallback: currentLanguage.label,
                ),
              },
            ),
            hint: chooseLanguageLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ExcludeSemantics(
                child: OpenIrnLanguageFlag(
                  key: ValueKey<String>(
                    'openirn-language-flag-current-${currentLanguage.code}',
                  ),
                  language: currentLanguage,
                  width: 26,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OpenIrnLanguageFlag extends StatelessWidget {
  final OpenIrnLanguage language;
  final double width;

  const OpenIrnLanguageFlag({
    required this.language,
    this.width = 30,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(width / 14);
    return SizedBox(
      width: width,
      height: width * 2 / 3,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.75,
          ),
          borderRadius: borderRadius,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: CustomPaint(painter: _OpenIrnLanguageFlagPainter(language)),
        ),
      ),
    );
  }
}

class _OpenIrnLanguageFlagPainter extends CustomPainter {
  final OpenIrnLanguage language;

  const _OpenIrnLanguageFlagPainter(this.language);

  @override
  void paint(Canvas canvas, Size size) {
    switch (language) {
      case OpenIrnLanguage.fr:
        _paintFrenchFlag(canvas, size);
        return;
      case OpenIrnLanguage.en:
        _paintUnitedKingdomFlag(canvas, size);
        return;
      case OpenIrnLanguage.es:
        _paintSpanishFlag(canvas, size);
        return;
      case OpenIrnLanguage.de:
        _paintGermanFlag(canvas, size);
        return;
    }
  }

  void _paintFrenchFlag(Canvas canvas, Size size) {
    final stripeWidth = size.width / 3;
    canvas
      ..drawRect(
        Rect.fromLTWH(0, 0, stripeWidth, size.height),
        Paint()..color = const Color(0xff0055a4),
      )
      ..drawRect(
        Rect.fromLTWH(stripeWidth, 0, stripeWidth, size.height),
        Paint()..color = Colors.white,
      )
      ..drawRect(
        Rect.fromLTWH(stripeWidth * 2, 0, stripeWidth, size.height),
        Paint()..color = const Color(0xffef4135),
      );
  }

  void _paintUnitedKingdomFlag(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff012169),
    );

    final whiteDiagonal = Paint()
      ..color = Colors.white
      ..strokeWidth = size.height * 0.24
      ..style = PaintingStyle.stroke;
    final redDiagonal = Paint()
      ..color = const Color(0xffc8102e)
      ..strokeWidth = size.height * 0.09
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), whiteDiagonal)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), whiteDiagonal)
      ..drawLine(Offset.zero, Offset(size.width, size.height), redDiagonal)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), redDiagonal)
      ..drawRect(
        Rect.fromLTWH(0, size.height * 0.34, size.width, size.height * 0.32),
        Paint()..color = Colors.white,
      )
      ..drawRect(
        Rect.fromLTWH(size.width * 0.38, 0, size.width * 0.24, size.height),
        Paint()..color = Colors.white,
      )
      ..drawRect(
        Rect.fromLTWH(0, size.height * 0.42, size.width, size.height * 0.16),
        Paint()..color = const Color(0xffc8102e),
      )
      ..drawRect(
        Rect.fromLTWH(size.width * 0.44, 0, size.width * 0.12, size.height),
        Paint()..color = const Color(0xffc8102e),
      );
  }

  void _paintSpanishFlag(Canvas canvas, Size size) {
    final stripeHeight = size.height / 4;
    final red = Paint()..color = const Color(0xffaa151b);
    canvas
      ..drawRect(Offset.zero & size, red)
      ..drawRect(
        Rect.fromLTWH(0, stripeHeight, size.width, stripeHeight * 2),
        Paint()..color = const Color(0xfff1bf00),
      );
  }

  void _paintGermanFlag(Canvas canvas, Size size) {
    final stripeHeight = size.height / 3;
    canvas
      ..drawRect(
        Rect.fromLTWH(0, 0, size.width, stripeHeight),
        Paint()..color = Colors.black,
      )
      ..drawRect(
        Rect.fromLTWH(0, stripeHeight, size.width, stripeHeight),
        Paint()..color = const Color(0xffdd0000),
      )
      ..drawRect(
        Rect.fromLTWH(0, stripeHeight * 2, size.width, stripeHeight),
        Paint()..color = const Color(0xffffce00),
      );
  }

  @override
  bool shouldRepaint(_OpenIrnLanguageFlagPainter oldDelegate) {
    return oldDelegate.language != language;
  }
}

class OpenIrnAppBarAction {
  final String id;
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool hidden;
  final bool destructive;
  final bool isDivider;

  const OpenIrnAppBarAction({
    required this.id,
    required this.label,
    this.icon,
    VoidCallback? onPressed,
    VoidCallback? onSelected,
    this.enabled = true,
    this.hidden = false,
    this.destructive = false,
  }) : onPressed = onPressed ?? onSelected,
       isDivider = false;

  const OpenIrnAppBarAction.divider({String? id})
    : id = id ?? '__divider__',
      icon = null,
      label = '',
      onPressed = null,
      enabled = false,
      hidden = false,
      destructive = false,
      isDivider = true;
}
