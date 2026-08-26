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
                      child: Text(
                        language.flag,
                        style: const TextStyle(fontSize: 22),
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
                child: Text(
                  currentLanguage.flag,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        );
      },
    );
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
