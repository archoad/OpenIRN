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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: OpenIrnLanguage.values.map((language) {
        final selected = i18n.language == language;
        final tooltipKey = switch (language) {
          OpenIrnLanguage.fr => 'common.language.switch_to_fr',
          OpenIrnLanguage.en => 'common.language.switch_to_en',
        };
        return Tooltip(
          message: context.tr(tooltipKey, fallback: language.label),
          child: Semantics(
            button: true,
            selected: selected,
            label: context.tr(
              'common.language.current',
              fallback: 'Langue actuelle : {language}',
              values: {'language': language.label},
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: selected
                  ? null
                  : () {
                      i18n.setLanguage(language);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.transparent,
                ),
                child: Text(
                  language.flag,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
