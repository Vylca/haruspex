import 'package:flutter/material.dart';

import '../editor/org_theme.dart';

/// A flat clickable area that turns orange (with black content) under the
/// mouse. [builder] gets whether it is hovered.
class HoverBox extends StatefulWidget {
  const HoverBox({
    super.key,
    required this.theme,
    required this.onTap,
    required this.builder,
    this.tooltip,
    this.onSecondaryTapDown,
    this.selected = false,
  });

  final OrgTheme theme;
  final VoidCallback? onTap;
  final Widget Function(bool hot) builder;
  final String? tooltip;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// Drawn as the current item (dim orange background) when not hovered.
  final bool selected;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final hot = _hot && widget.onTap != null;
    Widget child = MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: ColoredBox(
          color: hot ? t.accent : (widget.selected ? t.markerBg : Colors.transparent),
          child: widget.builder(hot),
        ),
      ),
    );
    final tip = widget.tooltip;
    if (tip != null) child = Tooltip(message: tip, child: child);
    return child;
  }
}
