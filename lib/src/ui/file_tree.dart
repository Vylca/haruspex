import 'package:flutter/material.dart';

import '../app/vault.dart';
import '../editor/org_theme.dart';

enum TreeAction { newNote, newFolder, rename, delete }

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
    final scheme = Theme.of(context).colorScheme;
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
          color: scheme.surfaceContainerLow,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
              child: Row(children: [
                Expanded(
                  child: Tooltip(
                    message: vault.root,
                    child: Text(
                      vault.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                _iconButton(Icons.note_add_outlined, 'New note', () => onAction(TreeAction.newNote, rootEntry)),
                _iconButton(
                    Icons.create_new_folder_outlined, 'New folder', () => onAction(TreeAction.newFolder, rootEntry)),
                _iconButton(Icons.unfold_less, 'Collapse all', vault.collapseAll),
                _iconButton(Icons.refresh, 'Refresh', vault.scan),
              ]),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapDown: (d) => _menu(context, rootEntry, d.globalPosition, isRoot: true),
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No notes yet. Create one with the + button.',
                            style: TextStyle(color: theme.faint)),
                      )
                    : ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onPressed) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: Icon(icon),
        onPressed: onPressed,
      );

  Widget _row(BuildContext context, VaultEntry e, int depth) {
    final active = !e.isDir && e.path == activePath;
    final open = e.isDir && vault.expanded.contains(e.path);
    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(context, e, d.globalPosition),
      child: InkWell(
        onTap: () => e.isDir ? vault.toggle(e.path) : onOpen(e.path),
        child: Container(
          color: active ? theme.markerBg : null,
          padding: EdgeInsets.fromLTRB(8.0 + 14.0 * depth, 4, 8, 4),
          child: Row(children: [
            Icon(
              e.isDir ? (open ? Icons.expand_more : Icons.chevron_right) : Icons.description_outlined,
              size: 16,
              color: theme.faint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                e.isDir ? e.name : stripNoteExtension(e.name),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? theme.accent : null,
                ),
              ),
            ),
          ]),
        ),
      ),
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
    }
  }
}
