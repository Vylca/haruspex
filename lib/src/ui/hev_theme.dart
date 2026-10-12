import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/org_theme.dart';

/// Scroll views stay put while Ctrl is held, so Ctrl+mouse wheel can zoom.
class HaruspexScrollBehavior extends MaterialScrollBehavior {
  const HaruspexScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => _NoCtrlScrollPhysics(parent: super.getScrollPhysics(context));
}

class _NoCtrlScrollPhysics extends ScrollPhysics {
  const _NoCtrlScrollPhysics({super.parent});

  @override
  _NoCtrlScrollPhysics applyTo(ScrollPhysics? ancestor) => _NoCtrlScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !HardwareKeyboard.instance.isControlPressed && super.shouldAcceptUserOffset(position);
}

/// A text field without any box, for prompts in the style of a minibuffer.
const InputDecoration minibufferDecoration = InputDecoration(
  isCollapsed: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  contentPadding: EdgeInsets.zero,
);

/// Hovered, focused or pressed: drawn inverted (black on orange).
bool _hot(Set<WidgetState> s) =>
    s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) || s.contains(WidgetState.pressed);

/// Square, flat buttons in the pixel font. Hover inverts them.
ButtonStyle pixelButtonStyle(OrgTheme t, {bool strong = false, bool outlined = true}) => ButtonStyle(
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      side: WidgetStateProperty.resolveWith((s) {
        if (!outlined) return BorderSide.none;
        if (s.contains(WidgetState.disabled)) return BorderSide(color: t.border);
        return BorderSide(color: strong || _hot(s) ? t.accent : t.border);
      }),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return Colors.transparent;
        if (_hot(s)) return t.accent;
        return strong ? t.markerBg : Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return t.faint;
        if (_hot(s)) return Colors.black;
        return t.accent;
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: pixelFont, fontSize: pixelSize)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      animationDuration: Duration.zero,
    );

/// Material theme for dialogs, menus and other widgets: black and orange,
/// square corners, one pixel borders, no ripples, everything in the pixel
/// font at its native size.
ThemeData buildHevTheme(OrgTheme t) {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: t.accent,
    onPrimary: Colors.black,
    primaryContainer: t.markerBg,
    onPrimaryContainer: t.accent,
    secondary: t.levels[1],
    onSecondary: Colors.black,
    secondaryContainer: t.panelHi,
    onSecondaryContainer: t.text,
    tertiary: t.levels[2],
    onTertiary: Colors.black,
    error: t.todo,
    onError: Colors.black,
    surface: t.panel,
    onSurface: t.text,
    onSurfaceVariant: t.faint,
    surfaceDim: t.panel,
    surfaceBright: t.panelHi,
    surfaceContainerLowest: t.panel,
    surfaceContainerLow: t.panel,
    surfaceContainer: t.panel,
    surfaceContainerHigh: t.panel,
    surfaceContainerHighest: t.panelHi,
    surfaceTint: Colors.transparent,
    outline: t.faint,
    outlineVariant: t.border,
    shadow: Colors.transparent,
    scrim: const Color(0xAA000000),
    inverseSurface: t.accent,
    onInverseSurface: Colors.black,
    inversePrimary: t.accentDim,
  );

  TextStyle px([Color? c]) => TextStyle(fontFamily: pixelFont, fontSize: pixelSize, height: 1.25, color: c ?? t.text);
  final text = TextTheme(
    displayLarge: px(),
    displayMedium: px(),
    displaySmall: px(),
    headlineLarge: px(t.accent),
    headlineMedium: px(t.accent),
    headlineSmall: px(t.accent),
    titleLarge: px(t.accent),
    titleMedium: px(),
    titleSmall: px(),
    bodyLarge: px(),
    bodyMedium: px(),
    bodySmall: px(t.faint),
    labelLarge: px(),
    labelMedium: px(),
    labelSmall: px(t.faint),
  );

  final squareBorder = OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: t.border));
  final input = InputDecorationThemeData(
    isDense: true,
    filled: true,
    fillColor: t.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    border: squareBorder,
    enabledBorder: squareBorder,
    disabledBorder: squareBorder,
    focusedBorder: squareBorder.copyWith(borderSide: BorderSide(color: t.accent)),
    errorBorder: squareBorder.copyWith(borderSide: BorderSide(color: t.todo)),
    focusedErrorBorder: squareBorder.copyWith(borderSide: BorderSide(color: t.todo)),
    hintStyle: px(t.faint),
    labelStyle: px(t.faint),
    floatingLabelStyle: px(t.accent),
    helperStyle: px(t.faint),
    prefixIconColor: t.faint,
    suffixIconColor: t.faint,
  );

  final menuShape = RoundedRectangleBorder(side: BorderSide(color: t.accentDim));
  final menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(t.panel),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(menuShape),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 2)),
    visualDensity: VisualDensity.compact,
  );
  final menuItem = ButtonStyle(
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
    // Menu items are text buttons inside; keep the text button border out.
    side: const WidgetStatePropertyAll(BorderSide.none),
    backgroundColor: WidgetStateProperty.resolveWith((s) => _hot(s) ? t.accent : Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return t.faint;
      return _hot(s) ? Colors.black : t.text;
    }),
    iconColor: WidgetStateProperty.resolveWith((s) => _hot(s) ? Colors.black : t.faint),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    textStyle: WidgetStatePropertyAll(px()),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    animationDuration: Duration.zero,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: pixelFont,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.panel,
    cardColor: t.panel,
    dividerColor: t.border,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    iconTheme: IconThemeData(color: t.accent, size: 16),
    inputDecorationTheme: input,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.selection,
      selectionHandleColor: t.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: Radius.zero,
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.dragged) ? t.accent : t.accentDim),
      crossAxisMargin: 0,
      mainAxisMargin: 0,
      minThumbLength: 24,
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: t.accent)),
      titleTextStyle: px(t.accent),
      contentTextStyle: px(),
      barrierColor: const Color(0x99000000),
      insetPadding: const EdgeInsets.all(32),
    ),
    textButtonTheme: TextButtonThemeData(style: pixelButtonStyle(t)),
    filledButtonTheme: FilledButtonThemeData(style: pixelButtonStyle(t, strong: true)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: pixelButtonStyle(t)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: pixelButtonStyle(t, strong: true)),
    iconButtonTheme: IconButtonThemeData(
      style: pixelButtonStyle(t, outlined: false).copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        minimumSize: const WidgetStatePropertyAll(Size(24, 24)),
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    menuTheme: MenuThemeData(style: menuStyle),
    menuBarTheme: MenuBarThemeData(
      style: menuStyle.copyWith(
        backgroundColor: WidgetStatePropertyAll(t.panel),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(style: menuItem),
    popupMenuTheme: PopupMenuThemeData(
      color: t.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: menuShape,
      textStyle: px(),
      labelTextStyle: WidgetStatePropertyAll(px()),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: px(), inputDecorationTheme: input, menuStyle: menuStyle),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.panel, border: Border.all(color: t.accentDim)),
      textStyle: px(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      waitDuration: const Duration(milliseconds: 600),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      side: BorderSide(color: t.faint),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Colors.black),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashRadius: 0,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(),
      dense: false,
      selectedColor: Colors.black,
      selectedTileColor: t.accent,
      iconColor: t.faint,
      textColor: t.text,
      titleTextStyle: px(),
      subtitleTextStyle: px(t.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 2,
      visualDensity: VisualDensity.compact,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: t.accent,
      inactiveTrackColor: t.border,
      thumbColor: t.accent,
      overlayColor: Colors.transparent,
      thumbShape: const _SquareThumb(),
      overlayShape: SliderComponentShape.noOverlay,
      tickMarkShape: SliderTickMarkShape.noTickMark,
      trackShape: const RectangularSliderTrackShape(),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(side: BorderSide(color: t.border)),
      side: BorderSide(color: t.border),
      backgroundColor: t.background,
      selectedColor: t.accent,
      checkmarkColor: Colors.black,
      labelStyle: px(),
      secondaryLabelStyle: const TextStyle(fontFamily: pixelFont, fontSize: pixelSize, color: Colors.black),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      indicator: BoxDecoration(color: t.accent),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: Colors.black,
      unselectedLabelColor: t.text,
      labelStyle: px(),
      unselectedLabelStyle: px(),
      dividerColor: t.border,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: t.panel,
      foregroundColor: t.accent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 36,
      titleTextStyle: px(t.accent),
      shape: Border(bottom: BorderSide(color: t.border)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: pixelButtonStyle(t).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected) || _hot(s)) return t.accent;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected) || _hot(s)) return Colors.black;
          return t.text;
        }),
        side: WidgetStatePropertyAll(BorderSide(color: t.accentDim)),
      ),
      selectedIcon: const SizedBox.shrink(),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      headerForegroundColor: t.accent,
      weekdayStyle: px(t.faint),
      dayStyle: px(),
      yearStyle: px(),
      dayShape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      yearShape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      dayForegroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.black;
        if (s.contains(WidgetState.disabled)) return t.faint;
        return t.text;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return t.accent;
        if (_hot(s)) return t.panelHi;
        return Colors.transparent;
      }),
      dayOverlayColor: const WidgetStatePropertyAll(Colors.transparent),
      todayForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : t.accent),
      todayBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : Colors.transparent),
      todayBorder: BorderSide(color: t.accent),
      yearForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : t.text),
      yearBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : Colors.transparent),
    ),
  );
}

/// Square slider handle.
class _SquareThumb extends SliderComponentShape {
  const _SquareThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(10, 14);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final c = Offset(center.dx.roundToDouble(), center.dy.roundToDouble());
    context.canvas.drawRect(
      Rect.fromCenter(center: c, width: 10, height: 14),
      Paint()..color = sliderTheme.thumbColor ?? Colors.orange,
    );
  }
}
