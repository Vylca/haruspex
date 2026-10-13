import 'package:flutter/material.dart';

import '../app/vault.dart';
import '../editor/org_theme.dart';
import 'pixel_widgets.dart';

enum TreeAction { newNote, newFolder, rename, delete, collapse, refresh }

/// Left sidebar listing the notes and folders of the vault.
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({
    super.key,
    required this.vault,
    required this.theme,
    required this.activePath,
    required this.onOpen,
    required this.onAction,
  });

  final Vault vault;
  final OrgTheme theme;
  final String? activePath;
  final void Function(String path) onOpen;
  final void Function(TreeAction action, VaultEntry target) onAction;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final rows = <Widget>[];
        void add(VaultEntry e, int depth) {
          for (final child in e.children) {
            rows.add(_row(context, child, depth));
            if (child.isDir && vault.expanded.contains(child.path)) add(child, depth + 1);
          }
        }

        add(vault.tree, 0);
        final rootEntry = VaultEntry(vault.root, true);
        return ColoredBox(
          color: t.panel,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 24,
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
              child: Row(children: [
                Expanded(
                  child: Tooltip(
                    message: vault.root,
                    child: Text(
                      vault.name.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.accent),
                    ),
                  ),
                ),
                _button('+', 'New note', () => onAction(TreeAction.newNote, rootEntry)),
                _button('+/', 'New folder', () => onAction(TreeAction.newFolder, rootEntry)),
                _button('-', 'Collapse all', vault.collapseAll),
              ]),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // On release, so a click on a row opens only the row's menu.
                onSecondaryTapUp: (d) => _menu(context, rootEntry, d.globalPosition, isRoot: true),
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('No notes yet. + makes one.', style: TextStyle(color: t.faint)),
                      )
                    : ListView(padding: const EdgeInsets.only(top: 2, bottom: 24), children: rows),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _button(String label, String tip, VoidCallback onPressed) => HoverBox(
        theme: theme,
        onTap: onPressed,
        tooltip: tip,
        builder: (hot) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(label, style: TextStyle(color: hot ? Colors.black : theme.faint)),
        ),
      );

  Widget _row(BuildContext context, VaultEntry e, int depth) {
    final t = theme;
    final active = !e.isDir && e.path == activePath;
    final open = e.isDir && vault.expanded.contains(e.path);
    return HoverBox(
      theme: t,
      selected: active,
      onTap: () => e.isDir ? vault.toggle(e.path) : onOpen(e.path),
      onSecondaryTapUp: (d) => _menu(context, e, d.globalPosition),
      builder: (hot) {
        final color = hot ? Colors.black : (active ? t.accent : (e.isDir ? t.levels[1] : t.text));
        return Padding(
          padding: EdgeInsets.fromLTRB(8.0 + 16.0 * depth, 0, 8, 0),
          child: Row(children: [
            SizedBox(
              width: 16,
              child: Text(e.isDir ? (open ? '\u25BE' : '\u25B8') : '', style: TextStyle(color: hot ? Colors.black : t.faint)),
            ),
            Expanded(
              child: Text(
                e.isDir ? '${e.name}/' : stripNoteExtension(e.name),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color),
              ),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, VaultEntry e, Offset global, {bool isRoot = false}) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final target = e.isDir ? e : VaultEntry(dirName(e.path), true);
    final choice = await showMenu<TreeAction>(
      context: context,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(value: TreeAction.newNote, child: Text('New note')),
        const PopupMenuItem(value: TreeAction.newFolder, child: Text('New folder')),
        if (isRoot) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: TreeAction.collapse, child: Text('Collapse all')),
          const PopupMenuItem(value: TreeAction.refresh, child: Text('Refresh')),
        ],
        if (!isRoot) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: TreeAction.rename, child: Text('Rename…')),
          const PopupMenuItem(value: TreeAction.delete, child: Text('Move to trash')),
        ],
      ],
    );
    if (choice == null) return;
    switch (choice) {
      case TreeAction.newNote:
      case TreeAction.newFolder:
        onAction(choice, target);
      case TreeAction.rename:
      case TreeAction.delete:
        onAction(choice, e);
      case TreeAction.collapse:
        vault.collapseAll();
      case TreeAction.refresh:
        vault.scan();
    }
  }
}
