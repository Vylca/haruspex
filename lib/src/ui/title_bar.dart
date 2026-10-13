import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/org_theme.dart';
import 'pixel_widgets.dart';

/// The app draws its own title bar: the system one is hidden at start.
class WindowChrome {
  WindowChrome._();

  /// True once the system title bar is hidden (desktop builds only; tests
  /// and other platforms keep the plain layout).
  static bool enabled = false;

  /// Hides the system title bar. Call before runApp.
  static Future<void> init() async {
    if (!Platform.isLinux) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      enabled = true;
    } catch (_) {
      enabled = false;
    }
  }

  /// Lets the window be resized from its edges when it has no frame.
  static Widget resizable(Widget child) =>
      enabled ? DragToResizeArea(resizeEdgeSize: 4, child: child) : child;
}

const _minimize = [
  '........',
  '........',
  '........',
  '........',
  '........',
  '........',
  '########',
  '########',
];

const _maximize = [
  '########',
  '########',
  '#......#',
  '#......#',
  '#......#',
  '#......#',
  '#......#',
  '########',
];

const _restore = [
  '..######',
  '..######',
  '..#....#',
  '######.#',
  '######.#',
  '#....###',
  '#....#..',
  '######..',
];

const _close = [
  '##....##',
  '###..###',
  '.######.',
  '..####..',
  '..####..',
  '.######.',
  '###..###',
  '##....##',
];

/// Top row of the window: logo, menus, title (drag to move, double click to
/// maximize, right click for the window menu) and the window buttons.
class TitleBar extends StatefulWidget {
  const TitleBar({
    super.key,
    required this.theme,
    required this.menu,
    required this.title,
    required this.onClose,
  });

  final OrgTheme theme;
  final Widget menu;
  final String title;
  final VoidCallback onClose;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (WindowChrome.enabled) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _maximized = v);
      });
    }
  }

  @override
  void dispose() {
    if (WindowChrome.enabled) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _button(List<String> art, String tip, VoidCallback onTap, {bool danger = false}) {
    final t = widget.theme;
    return HoverBox(
      theme: t,
      onTap: onTap,
      tooltip: tip,
      hotColor: danger ? t.todo : null,
      builder: (hot) => SizedBox(
        width: 36,
        height: 24,
        child: Center(child: PixelArt(art, color: hot ? Colors.black : t.faint, pixel: 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final on = WindowChrome.enabled;
    Widget title = SizedBox.expand(
      child: Center(
        child: Text(widget.title, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.faint)),
      ),
    );
    if (on) {
      title = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: windowManager.popUpWindowMenu,
        child: DragToMoveArea(child: title),
      );
    }
    return Container(
      height: 24,
      decoration: BoxDecoration(color: t.panel, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        // 16 px logo in the 23 px above the border, on a whole pixel row.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
          child: EarthLogo(color: t.accent, width: 18, stroke: 1.5),
        ),
        widget.menu,
        Expanded(child: title),
        if (on) ...[
          _button(_minimize, 'Minimize', windowManager.minimize),
          _button(_maximized ? _restore : _maximize, _maximized ? 'Restore' : 'Maximize', _toggleMaximize),
          _button(_close, 'Close', widget.onClose, danger: true),
        ],
      ]),
    );
  }
}
