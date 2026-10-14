import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/org_theme.dart';
import 'pixel_widgets.dart';

/// The app draws its own title bar: the system one is hidden at start. On
/// Linux the window has no frame at all and the app draws the window
/// buttons. On a Mac the system keeps its three buttons (and the resizable
/// frame) over the app's title bar.
class WindowChrome {
  WindowChrome._();

  /// True once the system title bar is hidden (desktop builds only; tests
  /// and other platforms keep the plain layout).
  static bool enabled = false;

  /// Running on macOS with the system's window buttons on the left.
  static bool mac = false;

  /// Called when the window's close button is pressed on a Mac, instead of
  /// closing right away, so unsaved changes can be saved.
  static VoidCallback? onClose;

  /// Hides the system title bar. Call before runApp.
  static Future<void> init() async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      await windowManager.ensureInitialized();
      if (Platform.isMacOS) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
        await windowManager.setPreventClose(true);
        windowManager.addListener(_CloseListener());
        mac = true;
      } else {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      }
      enabled = true;
    } catch (_) {
      enabled = false;
      mac = false;
    }
  }

  /// Lets the window be resized from its edges when it has no frame (the
  /// Mac window keeps its own).
  static Widget resizable(Widget child) =>
      enabled && !mac ? DragToResizeArea(resizeEdgeSize: 4, child: child) : child;

  /// Height of the title bar: on a Mac, the height the system buttons are
  /// centered in.
  static double get height => mac ? 28 : 24;
}

class _CloseListener with WindowListener {
  @override
  void onWindowClose() {
    final close = WindowChrome.onClose;
    if (close != null) {
      close();
    } else {
      windowManager.destroy();
    }
  }
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
    final mac = WindowChrome.mac;
    if (on) {
      title = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: mac ? null : windowManager.popUpWindowMenu,
        child: DragToMoveArea(child: title),
      );
    }
    final h = WindowChrome.height;
    return Container(
      height: h,
      decoration: BoxDecoration(color: t.panel, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        // Room for the Mac's close, minimize and zoom buttons.
        if (mac) const SizedBox(width: 72),
        // 16 px logo in the space above the border, on a whole pixel row.
        Padding(
          padding: EdgeInsets.fromLTRB(8, ((h - 17) / 2).floorToDouble(), 8, ((h - 17) / 2).ceilToDouble()),
          child: EarthLogo(color: t.accent, width: 18, stroke: 1.5),
        ),
        widget.menu,
        Expanded(child: title),
        if (on && !mac) ...[
          _button(_minimize, 'Minimize', windowManager.minimize),
          _button(_maximized ? _restore : _maximize, _maximized ? 'Restore' : 'Maximize', _toggleMaximize),
          _button(_close, 'Close', widget.onClose, danger: true),
        ],
      ]),
    );
  }
}
