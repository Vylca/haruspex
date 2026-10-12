import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

final String _sep = Platform.pathSeparator;

String baseName(String path) {
  final p = path.endsWith(_sep) ? path.substring(0, path.length - 1) : path;
  final i = p.lastIndexOf(_sep);
  return i < 0 ? p : p.substring(i + 1);
}

String dirName(String path) {
  final i = path.lastIndexOf(_sep);
  return i <= 0 ? _sep : path.substring(0, i);
}

String stripNoteExtension(String name) => name.replaceFirst(RegExp(r'\.(org|txt|org_archive)$', caseSensitive: false), '');

class VaultEntry {
  VaultEntry(this.path, this.isDir, [List<VaultEntry>? children]) : children = children ?? [];
  final String path;
  final bool isDir;
  final List<VaultEntry> children;
  String get name => baseName(path);
}

/// A folder of notes, like an Obsidian vault. The folder is marked by a
/// `.haruspex` directory that holds the workspace state (open tabs, expanded
/// folders). Deleted notes go to `.trash` in the vault.
class Vault extends ChangeNotifier {
  Vault(this.root);

  final String root;
  VaultEntry tree = VaultEntry('', true);
  List<String> notes = [];
  Set<String> expanded = {};
  final List<StreamSubscription<FileSystemEvent>> _watches = [];
  Timer? _debounce;
  bool _disposed = false;

  String get name => baseName(root);
  String get configDir => '$root$_sep.haruspex';

  /// Where the state lived before the app was renamed.
  String get _oldConfigDir => '$root$_sep.orgpad';
  String get trashDir => '$root$_sep.trash';
  File get _stateFile => File('$configDir${_sep}workspace.json');

  static bool isNote(String path) => RegExp(r'\.(org|txt|org_archive)$', caseSensitive: false).hasMatch(path);

  static bool isVault(String dir) =>
      Directory('$dir$_sep.haruspex').existsSync() || Directory('$dir$_sep.orgpad').existsSync();

  /// Creates the `.haruspex` folder if needed (taking over an `.orgpad`
  /// folder from before the rename) and scans the notes.
  Future<void> init() async {
    final old = Directory(_oldConfigDir);
    if (!await Directory(configDir).exists() && await old.exists()) {
      try {
        await old.rename(configDir);
      } catch (_) {
        // Keep going with a fresh folder.
      }
    }
    await Directory(configDir).create(recursive: true);
    final readme = File('$configDir${_sep}README.txt');
    await readme.writeAsString('This folder holds Haruspex settings for this vault. It is safe to delete.\n');
    await scan();
  }

  String relative(String path) {
    final prefix = '$root$_sep';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  bool contains(String path) => path.startsWith('$root$_sep');

  Future<void> scan() async {
    final found = <String>[];
    final dirs = <String>[root];

    Future<VaultEntry> walk(Directory d) async {
      final entry = VaultEntry(d.path, true);
      List<FileSystemEntity> items;
      try {
        items = await d.list(followLinks: false).toList();
      } catch (_) {
        return entry;
      }
      for (final it in items) {
        final name = baseName(it.path);
        if (name.startsWith('.')) continue;
        if (it is Directory) {
          dirs.add(it.path);
          entry.children.add(await walk(it));
        } else if (it is File && isNote(it.path)) {
          entry.children.add(VaultEntry(it.path, false));
          found.add(it.path);
        }
      }
      entry.children.sort((x, y) {
        if (x.isDir != y.isDir) return x.isDir ? -1 : 1;
        return x.name.toLowerCase().compareTo(y.name.toLowerCase());
      });
      return entry;
    }

    final t = await walk(Directory(root));
    if (_disposed) return;
    tree = t;
    found.sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));
    notes = found;
    _watchDirs(dirs);
    notifyListeners();
  }

  void _watchDirs(List<String> dirs) {
    for (final w in _watches) {
      w.cancel();
    }
    _watches.clear();
    for (final d in dirs) {
      try {
        _watches.add(Directory(d).watch().listen((_) => _scheduleScan(), onError: (_) {}));
      } catch (_) {
        // Watching is a convenience; the refresh button still works.
      }
    }
  }

  void _scheduleScan() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed) scan();
    });
  }

  /// Finds a note by name (with or without extension), like Obsidian links.
  String? findNote(String name) {
    final want = stripNoteExtension(name.trim()).toLowerCase();
    for (final n in notes) {
      if (stripNoteExtension(baseName(n)).toLowerCase() == want) return n;
      if (stripNoteExtension(relative(n)).toLowerCase() == want) return n;
    }
    return null;
  }

  String _unique(String dir, String name, String ext) {
    var candidate = '$dir$_sep$name$ext';
    var n = 2;
    while (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      candidate = '$dir$_sep$name $n$ext';
      n++;
    }
    return candidate;
  }

  Future<String> createNote(String dir, String name) async {
    final clean = stripNoteExtension(name.trim().isEmpty ? 'Untitled' : name.trim());
    final path = _unique(dir, clean, '.org');
    await File(path).writeAsString('#+TITLE: $clean\n\n');
    await scan();
    return path;
  }

  Future<String> createFolder(String dir, String name) async {
    final path = _unique(dir, name.trim().isEmpty ? 'New folder' : name.trim(), '');
    await Directory(path).create(recursive: true);
    expanded.add(path);
    await scan();
    return path;
  }

  Future<String> rename(String path, String newName) async {
    final isDir = FileSystemEntity.isDirectorySync(path);
    var name = newName.trim();
    if (!isDir && !isNote(name)) {
      final m = RegExp(r'\.(org|txt|org_archive)$', caseSensitive: false).firstMatch(path);
      name = '$name${m?.group(0) ?? '.org'}';
    }
    final target = '${dirName(path)}$_sep$name';
    if (isDir) {
      await Directory(path).rename(target);
    } else {
      await File(path).rename(target);
    }
    await scan();
    return target;
  }

  /// Moves a note or folder into the vault's `.trash` folder.
  Future<void> trash(String path) async {
    await Directory(trashDir).create(recursive: true);
    final name = baseName(path);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    final target = _unique(trashDir, stem, ext);
    if (FileSystemEntity.isDirectorySync(path)) {
      await Directory(path).rename(target);
    } else {
      await File(path).rename(target);
    }
    await scan();
  }

  Future<Map<String, dynamic>> loadState() async {
    try {
      if (await _stateFile.exists()) {
        final j = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
        expanded = ((j['expanded'] as List?)?.cast<String>() ?? const <String>[])
            .map((r) => '$root$_sep$r')
            .toSet();
        return j;
      }
    } catch (_) {
      // Start fresh.
    }
    return {};
  }

  Future<void> saveState({required List<String> open, String? active}) async {
    try {
      await Directory(configDir).create(recursive: true);
      await _stateFile.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'open': [for (final p in open) if (contains(p)) relative(p)],
        'active': active != null && contains(active) ? relative(active) : null,
        'expanded': [for (final e in expanded) if (contains(e)) relative(e)],
      }));
    } catch (_) {
      // Not fatal.
    }
  }

  String absolute(String relativePath) => '$root$_sep$relativePath';

  void toggle(String dir) {
    if (!expanded.remove(dir)) expanded.add(dir);
    notifyListeners();
  }

  void collapseAll() {
    expanded.clear();
    notifyListeners();
  }

  /// Expands the folders leading to [path].
  void revealPath(String path) {
    var d = dirName(path);
    var changed = false;
    while (d.length > root.length && d.startsWith(root)) {
      if (expanded.add(d)) changed = true;
      d = dirName(d);
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    for (final w in _watches) {
      w.cancel();
    }
    super.dispose();
  }
}
