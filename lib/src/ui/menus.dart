import 'package:flutter/material.dart';

/// The application menus, described once and shown either as the menu bar
/// inside the window (Linux) or in the macOS menu bar at the top of the
/// screen.
sealed class MenuNode {
  const MenuNode();
}

class MenuAction extends MenuNode {
  const MenuAction(this.label, this.onPressed, {this.shortcut, this.hint});

  final String label;

  /// Null: shown greyed out.
  final VoidCallback? onPressed;
  final SingleActivator? shortcut;

  /// Keys that cannot be a menu shortcut, such as the Org prefix "C-c C-t".
  final String? hint;
}

class MenuGroup extends MenuNode {
  const MenuGroup(this.label, this.children);

  final String label;
  final List<MenuNode> children;
}

class MenuSeparator extends MenuNode {
  const MenuSeparator();
}

/// The menu bar inside the window.
Widget windowMenuBar(List<MenuGroup> menus) => MenuBar(children: [for (final m in menus) _material(m)]);

Widget _material(MenuNode n) => switch (n) {
      MenuAction a => MenuItemButton(
          onPressed: a.onPressed,
          shortcut: a.shortcut,
          trailingIcon: a.hint == null ? null : Opacity(opacity: 0.6, child: Text(a.hint!)),
          child: Text(a.label),
        ),
      MenuGroup g => SubmenuButton(menuChildren: [for (final c in g.children) _material(c)], child: Text(g.label)),
      MenuSeparator() => const Divider(height: 1),
    };

/// The same menus for the macOS menu bar.
List<PlatformMenuItem> platformMenus(List<MenuGroup> menus) => [for (final m in menus) _platformMenu(m)];

PlatformMenu _platformMenu(MenuGroup g) => PlatformMenu(label: g.label, menus: _platformChildren(g.children));

/// Separators become groups, which macOS draws with a line between them.
List<PlatformMenuItem> _platformChildren(List<MenuNode> nodes) {
  final groups = <List<PlatformMenuItem>>[[]];
  for (final n in nodes) {
    switch (n) {
      case MenuSeparator():
        if (groups.last.isNotEmpty) groups.add([]);
      case MenuGroup g:
        groups.last.add(_platformMenu(g));
      case MenuAction a:
        groups.last.add(PlatformMenuItem(
          label: a.hint == null ? a.label : '${a.label}    ${a.hint}',
          shortcut: a.shortcut,
          onSelected: a.onPressed,
        ));
    }
  }
  groups.removeWhere((g) => g.isEmpty);
  if (groups.length == 1) return groups.first;
  return [for (final g in groups) PlatformMenuItemGroup(members: g)];
}

/// A standard macOS menu item, if this version of macOS and Flutter has it.
PlatformMenuItem? providedMenuItem(PlatformProvidedMenuItemType type) =>
    PlatformProvidedMenuItem.hasMenu(type) ? PlatformProvidedMenuItem(type: type) : null;
