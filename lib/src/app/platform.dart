import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// Keyboard and menu conventions of macOS: Cmd for application and
/// clipboard commands, Option for words, Cmd+arrows for lines. Org commands
/// (Ctrl+C prefix, Alt/Option+arrows) are the same everywhere, as in Emacs.
///
/// Follows the target platform rather than the host, so tests behave like
/// Linux unless they ask for macOS.
bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// Whether the modifier of application commands is held: Cmd on macOS, Ctrl
/// elsewhere.
bool get primaryPressed =>
    isMac ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;

/// An application shortcut: Cmd+[key] on macOS, Ctrl+[key] elsewhere.
SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: !isMac, meta: isMac, shift: shift);

/// Name of the application modifier, for help texts.
String get cmdName => isMac ? 'Cmd' : 'Ctrl';

/// Name of the Alt key (Option on a Mac), for help texts.
String get altName => isMac ? 'Option' : 'Alt';

/// A key description written for Linux, as it reads on a Mac: Cmd for
/// application commands, Option for Alt. Org commands keep Ctrl (Ctrl+C
/// prefix, Ctrl+Enter), and so does Ctrl+Tab.
String macKeys(String text) => text
    .replaceAll('Ctrl+H', 'Cmd+Shift+F')
    .replaceAllMapped(RegExp(r'Ctrl\+(?!C\b|Enter|Tab)'), (_) => 'Cmd+')
    .replaceAll('Alt+', 'Option+');

/// [text] with the key names of this platform.
String platformKeys(String text) => isMac ? macKeys(text) : text;

/// Opens a URL or a file with the system's default application.
Future<bool> openWithSystem(String target) async {
  final String command;
  if (Platform.isMacOS) {
    command = 'open';
  } else if (Platform.isLinux) {
    command = 'xdg-open';
  } else if (Platform.isWindows) {
    command = 'explorer';
  } else {
    return false;
  }
  try {
    await Process.start(command, [target], mode: ProcessStartMode.detached);
    return true;
  } catch (_) {
    return false;
  }
}

/// Folder for caches: ~/Library/Caches on macOS, $XDG_CACHE_HOME or
/// ~/.cache elsewhere.
String? cacheHome() {
  final env = Platform.environment;
  final home = env['HOME'];
  if (Platform.isMacOS) return home == null ? null : '$home/Library/Caches';
  return env['XDG_CACHE_HOME'] ?? (home == null ? null : '$home/.cache');
}
