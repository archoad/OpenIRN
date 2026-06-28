import 'package:flutter/material.dart';

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
    final visibleActions = actions.where((action) => !action.hidden).toList();

    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: true,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
      actions: [
        const SyncConnectivityIndicator(),
        const SizedBox(width: 2),
        if (visibleActions.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Actions',
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
                          action.label,
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
