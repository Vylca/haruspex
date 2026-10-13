import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/document.dart';
import '../app/settings.dart';
import '../app/vault.dart';
import '../app/version.dart';
import '../editor/highlighter.dart';
import '../editor/org_editor.dart';
import '../editor/org_theme.dart';
import '../org/agenda.dart';
import '../org/analysis.dart';
import '../org/edits.dart' show cycleTodo;
import 'agenda_page.dart';
import 'dialogs.dart';
import 'file_tree.dart';
import 'help.dart';
import 'hev_theme.dart';
import 'outline_panel.dart';
import 'pixel_widgets.dart';
import 'quick_switcher.dart';
import 'quotes.dart';
import 'settings_dialog.dart';
import 'title_bar.dart';
import 'tutorial.dart';

const _orgTypes = XTypeGroup(label: 'Org and text', extensions: ['org', 'txt', 'org_archive']);
const _allTypes = XTypeGroup(label: 'All files');

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.settings, required this.initialFiles});

  final AppSettings settings;
  final List<String> initialFiles;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> implements EditorHost {
  final OrgHighlighter highlighter = OrgHighlighter();
  final List<OrgDocument> docs = [];
  final Map<int, GlobalKey<OrgEditorState>> _editorKeys = {};
  int current = 0;

  /// The folder opened as a vault, if any.
  Vault? vault;

  String? _message;
  Timer? _messageTimer;
  bool _prefix = false;

  bool _findVisible = false;
  bool _replaceVisible = false;
  bool _caseSensitive = false;
  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();
  final FocusNode _findFocus = FocusNode(debugLabel: 'find');
  final FocusNode _dashFocus = FocusNode(debugLabel: 'dashboard');
  String _findStatus = '';

  late final AppLifecycleListener _lifecycle;

  AppSettings get settings => widget.settings;
  OrgDocument? get doc => docs.isEmpty ? null : docs[current.clamp(0, docs.length - 1)];
  OrgEditorState? get editor {
    final d = doc;
    return d == null ? null : _editorKeys[d.id]?.currentState;
  }

  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettings);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    _lifecycle.dispose();
    _messageTimer?.cancel();
    _wordTimer?.cancel();
    for (final d in docs) {
      d.dispose();
    }
    vault?.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _findFocus.dispose();
    _dashFocus.dispose();
    super.dispose();
  }

  void _onSettings() {
    highlighter.clearCache();
    if (mounted) setState(() {});
  }

  Future<void> _openInitial() async {
    var openedVault = false;
    for (final f in widget.initialFiles) {
      if (FileSystemEntity.isDirectorySync(f)) {
        await openVault(f);
        openedVault = true;
      }
    }
    if (!openedVault) {
      final last = settings.lastVault;
      if (last != null && Directory(last).existsSync() && Vault.isVault(last)) {
        await openVault(last);
      }
    }
    for (final f in widget.initialFiles) {
      if (!FileSystemEntity.isDirectorySync(f)) await openPath(f);
    }
    // Otherwise the dashboard shows, as in Doom Emacs.
    if (docs.isEmpty && vault == null && !settings.tutorialShown) {
      _addDoc(_newDoc(tutorialText));
      settings.update((s) => s.tutorialShown = true);
    }
  }

  // -------------------------------------------------------------------------
  // Documents
  // -------------------------------------------------------------------------

  OrgDocument _newDoc(String text, {String? path}) {
    final d = OrgDocument(highlighter: highlighter, text: text, path: path);
    _prepare(d);
    return d;
  }

  void _prepare(OrgDocument d) {
    d.controller.onMessage = showMessage;
    d.controller.applyStartup(foldDrawers: settings.foldDrawers);
    d.addListener(_onDocChanged);
    _editorKeys[d.id] = GlobalKey<OrgEditorState>();
  }

  void _onDocChanged() {
    if (mounted) setState(() {});
  }

  void _addDoc(OrgDocument d) {
    setState(() {
      docs.add(d);
      current = docs.length - 1;
    });
    _focusEditor();
    _saveVaultState();
  }

  void _focusEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final d = doc;
      if (d != null) {
        d.focusNode.requestFocus();
      } else {
        _dashFocus.requestFocus();
      }
    });
  }

  /// Ctrl+B: a scratch buffer, a throwaway note that is not a file. It
  /// closes without asking; Ctrl+S turns it into a file.
  void newScratch() {
    var n = 1;
    String name() => n == 1 ? '*scratch*' : '*scratch $n*';
    while (docs.any((d) => d.path == null && d.title == name())) {
      n++;
    }
    _addDoc(_newDoc('')
      ..scratch = true
      ..title = name());
  }

  /// Ctrl+N: a new note in the vault (next to the current note), or an
  /// untitled buffer when no folder is open.
  Future<void> newDocument() async {
    final v = vault;
    if (v == null) {
      _addDoc(_newDoc(''));
      return;
    }
    final p = doc?.path;
    final dir = p != null && v.contains(p) ? dirName(p) : v.root;
    final path = await v.createNote(dir, 'Untitled');
    final d = await openPath(path);
    if (d != null) {
      final end = d.controller.text.length;
      d.controller.selection = TextSelection.collapsed(offset: end);
    }
  }

  Future<void> openDialog() async {
    final files = await openFiles(acceptedTypeGroups: const [_orgTypes, _allTypes], initialDirectory: doc?.directory);
    for (final f in files) {
      await openPath(f.path);
    }
  }

  Future<OrgDocument?> openPath(String path, {bool focus = true}) async {
    final abs = File(path).absolute.path;
    final existing = docs.indexWhere((d) => d.path == abs);
    if (existing >= 0) {
      if (focus) {
        setState(() => current = existing);
        _focusEditor();
        vault?.revealPath(abs);
        _saveVaultState();
      }
      return docs[existing];
    }
    try {
      final d = await OrgDocument.load(abs, highlighter);
      _prepare(d);
      // Replace an empty untitled buffer.
      final cur = doc;
      if (cur != null && cur.path == null && !cur.scratch && !cur.dirty && cur.controller.text.isEmpty) {
        final i = docs.indexOf(cur);
        setState(() {
          docs[i] = d;
          current = i;
        });
        _disposeDoc(cur);
      } else {
        setState(() {
          docs.add(d);
          if (focus) current = docs.length - 1;
        });
      }
      settings.addRecent(abs);
      vault?.revealPath(abs);
      if (focus) _focusEditor();
      _saveVaultState();
      return d;
    } catch (e) {
      showMessage('Could not open $path: $e');
      return null;
    }
  }

  void _disposeDoc(OrgDocument d) {
    d.removeListener(_onDocChanged);
    _editorKeys.remove(d.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
  }

  Future<bool> save([OrgDocument? target]) async {
    final d = target ?? doc;
    if (d == null) return false;
    if (d.path == null) return saveAs(d);
    if (await d.changedOnDisk()) {
      if (!mounted) return false;
      final ok = await showConfirm(
        context,
        title: 'Changed on disk',
        message: '"${d.name}" was changed by another program since it was opened here. '
            'Overwrite it with this version?',
        ok: 'Overwrite',
      );
      if (!ok) return false;
    }
    try {
      await d.saveTo(d.path!);
      showMessage('Wrote ${d.path}');
      return true;
    } catch (e) {
      showMessage('Save failed: $e');
      return false;
    }
  }

  Future<bool> saveAs([OrgDocument? target]) async {
    final d = target ?? doc;
    if (d == null) return false;
    final name = d.path == null ? 'untitled.org' : d.name;
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [_orgTypes, _allTypes],
      suggestedName: name,
      initialDirectory: d.directory,
    );
    if (loc == null) return false;
    try {
      await d.saveTo(loc.path);
      settings.addRecent(loc.path);
      showMessage('Wrote ${loc.path}');
      return true;
    } catch (e) {
      showMessage('Save failed: $e');
      return false;
    }
  }

  /// F2: renames the current file on disk (or names an unsaved buffer).
  Future<void> renameDocument([OrgDocument? target]) async {
    final d = target ?? doc;
    if (d == null) return;
    final p = d.path;
    if (p == null) {
      final name = await showTextPrompt(context, title: 'Rename buffer', initial: d.name, label: 'Name');
      if (name == null || name.trim().isEmpty) return;
      setState(() => d.title = name.trim());
      _focusEditor();
      return;
    }
    final v = vault;
    final file = baseName(p);
    final inVault = v != null && v.contains(p);
    final initial = inVault ? stripNoteExtension(file) : file;
    final dot = initial.lastIndexOf('.');
    final name = await showTextPrompt(
      context,
      title: 'Rename',
      initial: initial,
      label: 'Name',
      selectTo: dot > 0 ? dot : null,
    );
    if (name != null && name.trim().isNotEmpty && name.trim() != initial) {
      await _renamePath(p, name);
    }
    _focusEditor();
  }

  /// Renames a file or folder on disk and points open tabs, recent files and
  /// the vault at the new name.
  Future<void> _renamePath(String path, String newName) async {
    final v = vault;
    try {
      final target = v != null && v.contains(path) ? await v.rename(path, newName) : await renameEntry(path, newName);
      if (target == path) return;
      String moved(String p) {
        if (p == path) return target;
        if (p.startsWith('$path${Platform.pathSeparator}')) return target + p.substring(path.length);
        return p;
      }

      setState(() {
        for (final d in docs) {
          final p = d.path;
          if (p != null) d.path = moved(p);
        }
      });
      settings.update((s) => s.recentFiles = [for (final f in s.recentFiles) moved(f)]);
      if (v != null) v.revealPath(target);
      _saveVaultState();
      showMessage('Renamed to ${baseName(target)}');
    } on FileSystemException catch (e) {
      showMessage('Could not rename: ${e.message}');
    }
  }

  Future<bool> _confirmClose(OrgDocument d) async {
    if (!d.dirty || (d.scratch && d.path == null)) return true;
    setState(() => current = docs.indexOf(d));
    final choice = await askSave(context, d.name);
    switch (choice) {
      case SaveChoice.save:
        return save(d);
      case SaveChoice.discard:
        return true;
      case SaveChoice.cancel:
        return false;
    }
  }

  Future<void> closeTab([int? index]) async {
    if (docs.isEmpty) return;
    final i = index ?? current;
    final d = docs[i];
    if (!await _confirmClose(d)) return;
    setState(() {
      docs.remove(d);
      if (docs.isEmpty) _nextQuote();
      if (current >= docs.length) current = docs.length - 1;
      if (current < 0) current = 0;
    });
    _disposeDoc(d);
    _focusEditor();
    _saveVaultState();
  }

  Future<bool> _closeAll() async {
    for (final d in [...docs]) {
      if (!await _confirmClose(d)) return false;
    }
    return true;
  }

  Future<AppExitResponse> _onExitRequested() async {
    await _saveVaultState();
    return await _closeAll() ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<void> quit() async {
    await _saveVaultState();
    if (await _closeAll()) {
      await ServicesBinding.instance.exitApplication(AppExitType.required);
    }
  }

  void _selectTab(int i) {
    if (i < 0 || i >= docs.length) return;
    setState(() => current = i);
    _focusEditor();
    final p = docs[i].path;
    if (p != null) vault?.revealPath(p);
    _saveVaultState();
  }

  // -------------------------------------------------------------------------
  // Vault (a folder of notes)
  // -------------------------------------------------------------------------

  Future<void> openVaultDialog() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Open folder');
    if (dir != null) await openVault(dir);
  }

  Future<void> openVault(String dir) async {
    final abs = Directory(dir).absolute.path;
    if (vault?.root == abs) return;
    await closeVault();
    final v = Vault(abs);
    try {
      await v.init();
    } catch (e) {
      showMessage('Could not open folder: $e');
      return;
    }
    final state = await v.loadState();
    setState(() {
      vault = v;
      settings.showFiles = true;
    });
    settings.addRecentVault(abs);
    final open = (state['open'] as List?)?.cast<String>() ?? const <String>[];
    for (final rel in open) {
      final p = v.absolute(rel);
      if (File(p).existsSync()) await openPath(p, focus: false);
    }
    final active = state['active'] as String?;
    if (active != null) {
      final i = docs.indexWhere((d) => d.path == v.absolute(active));
      if (i >= 0) _selectTab(i);
    } else if (docs.isNotEmpty) {
      _selectTab(docs.length - 1);
    }
    showMessage('Opened ${v.name}');
  }

  Future<void> closeVault() async {
    final v = vault;
    if (v == null) return;
    await _saveVaultState();
    for (final d in [...docs]) {
      final p = d.path;
      if (p != null && v.contains(p)) {
        if (!await _confirmClose(d)) return;
        final i = docs.indexOf(d);
        setState(() {
          docs.removeAt(i);
          if (current >= docs.length) current = docs.isEmpty ? 0 : docs.length - 1;
        });
        _disposeDoc(d);
      }
    }
    setState(() => vault = null);
    v.dispose();
    settings.update((s) => s.lastVault = null);
  }

  Future<void> _saveVaultState() async {
    final v = vault;
    if (v == null) return;
    await v.saveState(open: [for (final d in docs) if (d.path != null) d.path!], active: doc?.path);
  }

  Future<void> quickSwitch() async {
    final v = vault;
    if (v == null) {
      showMessage('Open a folder first (File > Open folder)');
      return;
    }
    final choice = await showQuickSwitcher(context, v);
    if (choice == null) return;
    if (choice.path != null) {
      await openPath(choice.path!);
    } else if (choice.create != null) {
      final path = await v.createNote(v.root, choice.create!);
      await openPath(path);
    }
  }

  Future<void> _treeAction(TreeAction action, VaultEntry target) async {
    final v = vault;
    if (v == null) return;
    try {
      switch (action) {
        case TreeAction.newNote:
          final name = await showTextPrompt(context, title: 'New note', initial: 'Untitled', label: 'Name');
          if (name == null || name.isEmpty) return;
          final path = await v.createNote(target.path, name);
          await openPath(path);
        case TreeAction.newFolder:
          final name = await showTextPrompt(context, title: 'New folder', initial: 'New folder', label: 'Name');
          if (name == null || name.isEmpty) return;
          await v.createFolder(target.path, name);
        case TreeAction.collapse:
          v.collapseAll();
        case TreeAction.refresh:
          await v.scan();
        case TreeAction.rename:
          final oldName = target.isDir ? target.name : stripNoteExtension(target.name);
          final name = await showTextPrompt(context, title: 'Rename', initial: oldName, label: 'Name');
          if (name == null || name.trim().isEmpty || name.trim() == oldName) return;
          await _renamePath(target.path, name);
        case TreeAction.delete:
          final ok = await showConfirm(context,
              title: 'Move to trash',
              message: 'Move "${target.name}" to the vault\'s .trash folder?',
              ok: 'Move to trash');
          if (!ok) return;
          for (final d in [...docs]) {
            final p = d.path;
            if (p == null) continue;
            if (p == target.path || p.startsWith('${target.path}${Platform.pathSeparator}')) {
              final i = docs.indexOf(d);
              setState(() {
                docs.removeAt(i);
                if (current >= docs.length) current = docs.isEmpty ? 0 : docs.length - 1;
              });
              _disposeDoc(d);
            }
          }
          await v.trash(target.path);
          _saveVaultState();
      }
    } catch (e) {
      showMessage('Failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // EditorHost
  // -------------------------------------------------------------------------

  @override
  void showMessage(String message) {
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  void setPrefixActive(bool active) => setState(() => _prefix = active);

  @override
  void openAgenda() => _openAgenda();

  @override
  Future<void> openLink(String target, OrgDocument from) async {
    var t = target.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('ftp://') ||
        lower.startsWith('news:') ||
        lower.startsWith('doi:')) {
      _openExternal(lower.startsWith('doi:') ? 'https://doi.org/${t.substring(4)}' : t);
      return;
    }
    if (lower.startsWith('id:')) {
      final id = t.substring(3).trim();
      for (final d in docs) {
        final a = d.controller.analysis;
        for (final h in a.headingLines) {
          if (a.properties(h)['ID'] == id) {
            _selectTab(docs.indexOf(d));
            _jump(d, h);
            return;
          }
        }
      }
      showMessage('No entry with ID $id in open files');
      return;
    }
    String? search;
    var isFile = false;
    if (lower.startsWith('file:')) {
      t = t.substring(5);
      isFile = true;
    }
    final sep = t.indexOf('::');
    if (sep >= 0) {
      search = t.substring(sep + 2);
      t = t.substring(0, sep);
      isFile = true;
    }
    if (t.isEmpty && search != null) {
      _searchInDoc(from, search);
      return;
    }
    if (!isFile && (t.startsWith('/') || t.startsWith('./') || t.startsWith('../') || t.startsWith('~/'))) {
      isFile = true;
    }
    if (!isFile && RegExp(r'\.(org|txt|org_archive)$', caseSensitive: false).hasMatch(t)) isFile = true;
    if (!isFile) {
      _searchInDoc(from, t);
      return;
    }
    var path = t;
    if (path.startsWith('~/')) path = '${Platform.environment['HOME'] ?? ''}${path.substring(1)}';
    if (!path.startsWith('/')) {
      final dir = from.directory ?? Directory.current.path;
      path = '$dir/$path';
    }
    if (RegExp(r'\.(org|txt|org_archive)$', caseSensitive: false).hasMatch(path)) {
      if (!File(path).existsSync()) {
        showMessage('No such file: $path');
        return;
      }
      final d = await openPath(path);
      if (d != null && search != null && search.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _searchInDoc(d, search!));
      }
      return;
    }
    _openExternal(path);
  }

  void _searchInDoc(OrgDocument d, String target) {
    final a = d.controller.analysis;
    var t = target.trim();
    if (t.startsWith('*')) {
      final want = plainTitle(t.substring(1)).toLowerCase();
      for (final h in a.headingLines) {
        if (plainTitle(a.headingInfo(h)!.title(a.lines[h])).toLowerCase() == want) {
          _jump(d, h);
          return;
        }
      }
      showMessage('No heading "$want"');
      return;
    }
    if (t.startsWith('#')) {
      final id = t.substring(1);
      for (final h in a.headingLines) {
        if (a.properties(h)['CUSTOM_ID'] == id) {
          _jump(d, h);
          return;
        }
      }
      showMessage('No entry with CUSTOM_ID $id');
      return;
    }
    // Dedicated target <<t>>, then a heading with that title, then plain text.
    final targetIdx = a.text.toLowerCase().indexOf('<<${t.toLowerCase()}>>');
    if (targetIdx >= 0) {
      _jump(d, a.lineOfOffset(targetIdx));
      return;
    }
    for (final h in a.headingLines) {
      if (plainTitle(a.headingInfo(h)!.title(a.lines[h])).toLowerCase() == t.toLowerCase()) {
        _jump(d, h);
        return;
      }
    }
    // A note of that name in the vault, like an Obsidian link.
    final note = vault?.findNote(t);
    if (note != null) {
      openPath(note);
      return;
    }
    final idx = a.text.toLowerCase().indexOf(t.toLowerCase());
    if (idx >= 0) {
      _jump(d, a.lineOfOffset(idx));
      return;
    }
    showMessage('No match for "$t"');
  }

  void _jump(OrgDocument d, int line) {
    final i = docs.indexOf(d);
    if (i >= 0 && i != current) setState(() => current = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorKeys[d.id]?.currentState?.jumpToLine(line);
    });
  }

  void _openExternal(String target) {
    if (Platform.isLinux) {
      Process.start('xdg-open', [target], mode: ProcessStartMode.detached).then<void>(
        (_) {},
        onError: (Object e) => showMessage('Could not open $target'),
      );
      showMessage('Opening $target');
    } else {
      showMessage('Opening external links is not supported on this platform yet');
    }
  }

  // -------------------------------------------------------------------------
  // Agenda
  // -------------------------------------------------------------------------

  List<AgendaSource> _agendaSources() {
    final sources = <AgendaSource>[];
    final openPaths = <String>{};
    for (final d in docs) {
      sources.add(AgendaSource('doc:${d.id}', d.name, d.controller.text));
      if (d.path != null) openPaths.add(d.path!);
    }
    final files = <String>{...settings.agendaFiles, ...?vault?.notes.where((n) => !n.endsWith('.txt'))};
    for (final f in files) {
      if (openPaths.contains(f)) continue;
      try {
        final text = File(f).readAsStringSync().replaceAll('\r\n', '\n');
        sources.add(AgendaSource('file:$f', f.split(Platform.pathSeparator).last, text));
      } catch (_) {
        // Skip unreadable agenda files.
      }
    }
    return sources;
  }

  Future<OrgDocument?> _docForSource(String sourceId) async {
    if (sourceId.startsWith('doc:')) {
      final id = int.tryParse(sourceId.substring(4));
      for (final d in docs) {
        if (d.id == id) return d;
      }
      return null;
    }
    if (sourceId.startsWith('file:')) return openPath(sourceId.substring(5), focus: false);
    return null;
  }

  Future<void> _openAgenda() async {
    final theme = settings.orgTheme;
    final item = await Navigator.of(context).push<AgendaItem>(PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondary) => AgendaPage(
        sources: _agendaSources,
        theme: theme,
        onCycleTodo: (item) async {
          final d = await _docForSource(item.sourceId);
          if (d == null) return;
          final a = d.controller.analysis;
          if (item.line >= a.lineCount) return;
          final r = cycleTodo(a, a.lineStarts[item.line]);
          if (r != null) d.controller.applyEdit(r);
        },
      ),
    ));
    if (item == null || !mounted) return;
    final d = await _docForSource(item.sourceId);
    if (d == null) return;
    _selectTab(docs.indexOf(d));
    _jump(d, item.line);
  }

  // -------------------------------------------------------------------------
  // Find / replace
  // -------------------------------------------------------------------------

  void _showFind({bool replace = false}) {
    final e = editor;
    final d = doc;
    if (d != null && e != null) {
      final sel = d.controller.selection;
      if (sel.isValid && !sel.isCollapsed) {
        final s = d.controller.text.substring(sel.start, sel.end);
        if (!s.contains('\n')) _findCtrl.text = s;
      }
    }
    setState(() {
      _findVisible = true;
      _replaceVisible = replace;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocus.requestFocus();
      _findCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _findCtrl.text.length);
    });
  }

  void _hideFind() {
    setState(() => _findVisible = false);
    _focusEditor();
  }

  void _find({required bool forward, bool incremental = false}) {
    final e = editor;
    if (e == null) return;
    final q = _findCtrl.text;
    final found =
        e.find(q, forward: forward, caseSensitive: _caseSensitive, fromSelectionStart: incremental, focus: false);
    final n = e.countMatches(q, caseSensitive: _caseSensitive);
    setState(() => _findStatus = q.isEmpty ? '' : (found ? '$n match${n == 1 ? '' : 'es'}' : 'No match'));
    if (!incremental) _findFocus.requestFocus();
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  void _command(String id) {
    final e = editor;
    if (e == null) return;
    e.runCommand(id);
  }

  void _zoom(double delta) {
    settings.update((s) {
      s.fontSize = delta == 0 ? 16.0 : (s.fontSize + delta).clamp(9.0, 40.0);
    });
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): newDocument,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): newScratch,
        const SingleActivator(LogicalKeyboardKey.f2): () => renameDocument(),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): openDialog,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => save(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => saveAs(),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => closeTab(),
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): quit,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _showFind(),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () => _showFind(replace: true),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () {
          if (docs.isNotEmpty) _selectTab((current + 1) % docs.length);
        },
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () {
          if (docs.isNotEmpty) _selectTab((current - 1 + docs.length) % docs.length);
        },
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): quickSwitch,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true): () =>
            settings.update((s) => s.showFiles = !s.showFiles),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _zoom(1),
        const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true): () => _zoom(1),
        const SingleActivator(LogicalKeyboardKey.add, control: true): () => _zoom(1),
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () => _zoom(1),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _zoom(-1),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () => _zoom(-1),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => _zoom(0),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true): () =>
            settings.update((s) => s.showOutline = !s.showOutline),
      };

  @override
  Widget build(BuildContext context) {
    final orgTheme = settings.orgTheme;
    if (!identical(highlighter.theme, orgTheme)) {
      highlighter.theme = orgTheme;
      highlighter.clearCache();
    }
    if (highlighter.hideMarkup != settings.hideMarkup ||
        highlighter.scaleHeadings != settings.scaleHeadings ||
        highlighter.superstar != settings.superstar) {
      highlighter.hideMarkup = settings.hideMarkup;
      highlighter.scaleHeadings = settings.scaleHeadings;
      highlighter.superstar = settings.superstar;
      highlighter.clearCache();
    }
    highlighter.baseFontSize = settings.fontSize;
    if (highlighter.monoFamily != settings.codeFontFamily) {
      highlighter.monoFamily = settings.codeFontFamily;
      highlighter.clearCache();
    }

    final t = orgTheme;
    final d = doc;
    final v = vault;
    return Scaffold(
      backgroundColor: t.background,
      body: WindowChrome.resizable(Listener(
        onPointerSignal: _onPointerSignal,
        child: CallbackShortcuts(
        bindings: _shortcuts,
        child: Column(children: [
          TitleBar(
            theme: t,
            menu: _menuBar(context, t),
            title: d == null ? 'Haruspex' : '${d.dirty && !d.scratch ? '● ' : ''}${d.name} · Haruspex',
            onClose: quit,
          ),
          if (docs.isNotEmpty) _tabBar(context, t),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final showFiles = v != null && settings.showFiles;
              final showOutline = settings.showOutline && d != null;
              // Keep at least this much room for the text.
              const minEditor = 320.0;
              final double files = showFiles
                  ? _filesWidth.clamp(_minPanel,
                      math.max<double>(_minPanel, box.maxWidth - minEditor - (showOutline ? _outlineWidth : 0.0)))
                  : 0.0;
              final double outline = showOutline
                  ? _outlineWidth.clamp(_minPanel, math.max<double>(_minPanel, box.maxWidth - minEditor - files))
                  : 0.0;
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (v != null && showFiles) ...[
                  SizedBox(
                    width: files,
                    child: FileTreePanel(
                      vault: v,
                      theme: t,
                      activePath: d?.path,
                      onOpen: (p) => openPath(p),
                      onAction: _treeAction,
                    ),
                  ),
                  PanelSplitter(
                    theme: t,
                    onDrag: (dx) => setState(() => _dragFiles = files + dx),
                    onDragEnd: () => _saveWidths(),
                    onReset: () => settings.update((s) => s.filesWidth = AppSettings.defaultFilesWidth),
                  ),
                ],
                Expanded(
                  child: docs.isEmpty
                      ? _dashboard(context, t)
                      : IndexedStack(
                          index: current.clamp(0, docs.length - 1),
                          children: [
                            for (final x in docs)
                              OrgEditor(key: _editorKeys[x.id], doc: x, host: this, settings: settings),
                          ],
                        ),
                ),
                if (d != null && showOutline) ...[
                  PanelSplitter(
                    theme: t,
                    onDrag: (dx) => setState(() => _dragOutline = outline - dx),
                    onDragEnd: () => _saveWidths(),
                    onReset: () => settings.update((s) => s.outlineWidth = AppSettings.defaultOutlineWidth),
                  ),
                  SizedBox(
                    width: outline,
                    child: OutlinePanel(
                      doc: d,
                      theme: t,
                      onJump: (line) => editor?.jumpToLine(line),
                    ),
                  ),
                ],
              ]);
            }),
          ),
          _modeLine(context, t),
          _findVisible ? _findBar(context, t) : _echoArea(t),
        ]),
      ))),
    );
  }

  // -------------------------------------------------------------------------
  // Side panel widths and Ctrl+wheel zoom
  // -------------------------------------------------------------------------

  static const double _minPanel = 140;

  /// Widths while a splitter is being dragged; saved when the drag ends.
  double? _dragFiles, _dragOutline;

  double get _filesWidth => _dragFiles ?? settings.filesWidth;
  double get _outlineWidth => _dragOutline ?? settings.outlineWidth;

  void _saveWidths() {
    final f = _dragFiles, o = _dragOutline;
    _dragFiles = null;
    _dragOutline = null;
    settings.update((s) {
      if (f != null) s.filesWidth = math.max<double>(_minPanel, f).roundToDouble();
      if (o != null) s.outlineWidth = math.max<double>(_minPanel, o).roundToDouble();
    });
  }

  double _wheel = 0;

  /// Ctrl+mouse wheel zooms. Scroll views ignore the wheel while Ctrl is
  /// held (see HaruspexScrollBehavior), so the event comes here.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (e is! PointerScrollEvent) return;
      _wheel += e.scrollDelta.dy;
      // One wheel notch is about 53 pixels.
      while (_wheel <= -40) {
        _wheel += 53;
        _zoom(1);
      }
      while (_wheel >= 40) {
        _wheel -= 53;
        _zoom(-1);
      }
      if (_wheel.abs() < 40) _wheel = 0;
    });
  }

  // -------------------------------------------------------------------------
  // Dashboard, shown when nothing is open
  // -------------------------------------------------------------------------

  List<(String, String, String, VoidCallback)> get _dashItems {
    final v = vault;
    return [
      ('n', v == null ? 'New file' : 'New note', 'Ctrl+N', newDocument),
      ('b', 'Scratch buffer', 'Ctrl+B', newScratch),
      if (v != null) ('p', 'Find note', 'Ctrl+P', quickSwitch),
      ('o', 'Open file', 'Ctrl+O', openDialog),
      ('f', v == null ? 'Open folder as vault' : 'Open another folder', '', openVaultDialog),
      if (v != null || settings.agendaFiles.isNotEmpty) ('a', 'Agenda', 'C-c a', _openAgenda),
      ('t', 'Tutorial', '', () => _addDoc(_newDoc(tutorialText))),
      ('s', 'Settings', '', () => showSettingsDialog(context, settings)),
    ];
  }

  /// The dashboard's line from the Book of the Law; a new one each time the
  /// dashboard shows, or on click.
  int _quoteIndex = math.Random().nextInt(crowleyQuotes.length);

  void _nextQuote() {
    if (crowleyQuotes.length < 2) return;
    var n = _quoteIndex;
    while (n == _quoteIndex) {
      n = math.Random().nextInt(crowleyQuotes.length);
    }
    _quoteIndex = n;
  }

  Widget _quote(OrgTheme t, TextStyle base) {
    final (text, verse) = crowleyQuotes[_quoteIndex % crowleyQuotes.length];
    return GestureDetector(
      onTap: () => setState(_nextQuote),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 520,
          child: Column(children: [
            Text(text, textAlign: TextAlign.center, style: base.copyWith(color: t.levels[1], fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text('Aleister Crowley, Liber AL $verse', textAlign: TextAlign.center, style: base.copyWith(color: t.faint)),
          ]),
        ),
      ),
    );
  }

  Widget _dashboard(BuildContext context, OrgTheme t) {
    final items = _dashItems;
    final recent = settings.recentFiles.where((f) => File(f).existsSync()).take(5).toList();
    final v = vault;
    final base = TextStyle(fontFamily: pixelFont, fontSize: pixelSize, height: 1.25, color: t.text);

    Widget row(String key, String label, String hint, VoidCallback onTap) => HoverBox(
          theme: t,
          onTap: onTap,
          builder: (hot) => Row(mainAxisSize: MainAxisSize.min, children: [
            Text('[$key]', style: base.copyWith(color: hot ? Colors.black : t.accent)),
            const SizedBox(width: 16),
            SizedBox(
              width: 280,
              child: Text(label, overflow: TextOverflow.ellipsis, style: base.copyWith(color: hot ? Colors.black : t.text)),
            ),
            SizedBox(
              width: 96,
              child: Text(hint, textAlign: TextAlign.right, style: base.copyWith(color: hot ? Colors.black : t.faint)),
            ),
          ]),
        );

    return Focus(
      focusNode: _dashFocus,
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final keys = HardwareKeyboard.instance;
        if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) return KeyEventResult.ignored;
        final ch = e.character?.toLowerCase();
        if (ch == null) return KeyEventResult.ignored;
        for (final (k, _, _, run) in items) {
          if (k == ch) {
            run();
            return KeyEventResult.handled;
          }
        }
        final n = int.tryParse(ch);
        if (n != null && n >= 1 && n <= recent.length) {
          openPath(recent[n - 1]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dashFocus.requestFocus,
        child: ColoredBox(
          color: t.background,
          child: LayoutBuilder(builder: (context, c) {
            // Whole-pixel squares, as large as the space allows.
            final short = c.maxHeight < 600;
            final fit = ((c.maxWidth - 64) / PixelBanner.widthOf('HARUSPEX')).floorToDouble();
            final pixel = fit.clamp(3.0, short ? 6.0 : 10.0);
            return Center(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  PixelArt(logoRows, color: t.accent, pixel: short ? 3 : 4),
                  SizedBox(height: short ? 12 : 20),
                  PixelBanner('HARUSPEX', color: t.accent, pixel: pixel),
                  const SizedBox(height: 12),
                  Text(
                    v == null ? 'plain text, org mode' : 'vault: ${v.name}',
                    style: base.copyWith(color: t.faint),
                  ),
                  const SizedBox(height: 20),
                  _quote(t, base),
                  const SizedBox(height: 24),
                  for (final (k, label, hint, run) in items) row(k, label, hint, run),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 432,
                      child: Text('Recent files', style: base.copyWith(color: t.levels[1])),
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < recent.length; i++)
                      row('${i + 1}', baseName(recent[i]), '', () => openPath(recent[i])),
                  ],
                  const SizedBox(height: 28),
                  Text('Haruspex $appVersion', style: base.copyWith(color: t.faint)),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Menu bar and tabs
  // -------------------------------------------------------------------------

  Widget _menuBar(BuildContext context, OrgTheme t) {
    MenuItemButton item(String label, VoidCallback? onPressed, {MenuSerializableShortcut? shortcut, String? hint}) {
      return MenuItemButton(
        onPressed: onPressed,
        shortcut: shortcut,
        trailingIcon: hint == null ? null : Opacity(opacity: 0.6, child: Text(hint)),
        child: Text(label),
      );
    }

    final hasDoc = doc != null;
    VoidCallback? cmd(String id) => hasDoc ? () => _command(id) : null;

    return MenuBar(
      children: [
        SubmenuButton(menuChildren: [
          item(vault == null ? 'New file' : 'New note', newDocument,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true)),
          item('New scratch buffer', newScratch, shortcut: const SingleActivator(LogicalKeyboardKey.keyB, control: true)),
          item('Open file…', openDialog, shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true)),
          SubmenuButton(
            menuChildren: [
              if (settings.recentFiles.isEmpty) item('(none)', null),
              for (final f in settings.recentFiles) item(f, () => openPath(f)),
            ],
            child: const Text('Open recent file'),
          ),
          const Divider(height: 1),
          item('Open folder as vault…', openVaultDialog),
          SubmenuButton(
            menuChildren: [
              if (settings.recentVaults.isEmpty) item('(none)', null),
              for (final f in settings.recentVaults) item(f, () => openVault(f)),
            ],
            child: const Text('Open recent folder'),
          ),
          item('Quick switcher…', vault == null ? null : quickSwitch,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyP, control: true)),
          item('Close folder', vault == null ? null : closeVault),
          const Divider(height: 1),
          item('Save', hasDoc ? () => save() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true)),
          item('Save as…', hasDoc ? () => saveAs() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true)),
          item('Rename…', hasDoc ? () => renameDocument() : null, shortcut: const SingleActivator(LogicalKeyboardKey.f2)),
          const Divider(height: 1),
          item('Close tab', hasDoc ? () => closeTab() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyW, control: true)),
          item('Quit', quit, shortcut: const SingleActivator(LogicalKeyboardKey.keyQ, control: true)),
        ], child: const Text('File')),
        SubmenuButton(menuChildren: [
          item('Undo', hasDoc ? () => editor?.undo() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true)),
          item('Redo', hasDoc ? () => editor?.redo() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true)),
          const Divider(height: 1),
          item('Cut', hasDoc ? () => editor?.cutSelection() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyX, control: true)),
          item('Copy', hasDoc ? () => editor?.copySelection() : null, hint: 'Ctrl+C (with selection)'),
          item('Paste', hasDoc ? () => editor?.paste() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyV, control: true)),
          item('Select all', hasDoc ? () => editor?.selectAll() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyA, control: true)),
          const Divider(height: 1),
          item('Find…', hasDoc ? () => _showFind() : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyF, control: true)),
          item('Replace…', hasDoc ? () => _showFind(replace: true) : null,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyH, control: true)),
        ], child: const Text('Edit')),
        SubmenuButton(menuChildren: [
          SubmenuButton(menuChildren: [
            item('Cycle at caret', cmd('cycle'), hint: 'Tab'),
            item('Cycle document', cmd('globalCycle'), hint: 'Shift+Tab'),
            item('Overview', cmd('overview')),
            item('Contents', cmd('contents')),
            item('Show all', cmd('showAll')),
          ], child: const Text('Visibility')),
          SubmenuButton(menuChildren: [
            item('New heading', cmd('insertHeading'), hint: 'Alt+Enter'),
            item('New TODO heading', cmd('insertTodoHeading'), hint: 'Alt+Shift+Enter'),
            item('New heading after subtree', cmd('insertHeadingAfter'), hint: 'Ctrl+Enter'),
            item('Promote', cmd('promote'), hint: 'Alt+Left'),
            item('Demote', cmd('demote'), hint: 'Alt+Right'),
            item('Promote subtree', cmd('promoteTree'), hint: 'Alt+Shift+Left'),
            item('Demote subtree', cmd('demoteTree'), hint: 'Alt+Shift+Right'),
            item('Move up', cmd('moveUp'), hint: 'Alt+Up'),
            item('Move down', cmd('moveDown'), hint: 'Alt+Down'),
            item('Toggle heading', cmd('toggleHeading'), hint: 'C-c *'),
          ], child: const Text('Structure')),
          const Divider(height: 1),
          item('Cycle TODO', cmd('todo'), hint: 'C-c C-t'),
          item('Priority…', cmd('priority'), hint: 'C-c ,'),
          item('Tags…', cmd('tags'), hint: 'C-c C-q'),
          item('Schedule…', cmd('schedule'), hint: 'C-c C-s'),
          item('Deadline…', cmd('deadline'), hint: 'C-c C-d'),
          item('Timestamp…', cmd('timestamp'), hint: 'C-c .'),
          item('Inactive timestamp…', cmd('inactiveTimestamp'), hint: 'C-c !'),
          const Divider(height: 1),
          item('New list item', cmd('insertItem'), hint: 'Alt+Enter'),
          item('Toggle checkbox', cmd('checkbox'), hint: 'C-c C-c'),
          item('Add/remove checkbox', cmd('checkboxPresence'), hint: 'C-c C-x'),
          item('Update statistics', cmd('statistics'), hint: 'C-c #'),
          const Divider(height: 1),
          item('Insert / align table', cmd('table'), hint: 'C-c |'),
          item('Insert table rule', cmd('tableHline'), hint: 'C-c -'),
          const Divider(height: 1),
          item('Insert link…', cmd('link'), hint: 'C-c C-l'),
          item('Open link', cmd('openLink'), hint: 'C-c C-o'),
          const Divider(height: 1),
          item('Agenda', hasDoc || vault != null ? _openAgenda : null, hint: 'C-c a'),
        ], child: const Text('Org')),
        SubmenuButton(menuChildren: [
          item(settings.showFiles ? 'Hide files' : 'Show files',
              vault == null ? null : () => settings.update((s) => s.showFiles = !s.showFiles),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true)),
          item(settings.showOutline ? 'Hide outline' : 'Show outline',
              () => settings.update((s) => s.showOutline = !s.showOutline),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true)),
          item(settings.lineNumbers ? 'Hide line numbers' : 'Show line numbers',
              () => settings.update((s) => s.lineNumbers = !s.lineNumbers)),
          item('Zoom in', () => _zoom(1), shortcut: const SingleActivator(LogicalKeyboardKey.equal, control: true)),
          item('Zoom out', () => _zoom(-1), shortcut: const SingleActivator(LogicalKeyboardKey.minus, control: true)),
          item('Reset zoom', () => _zoom(0), shortcut: const SingleActivator(LogicalKeyboardKey.digit0, control: true)),
          const Divider(height: 1),
          item('Dashboard', docs.isEmpty ? null : _showDashboard),
          item('Settings…', () => showSettingsDialog(context, settings)),
        ], child: const Text('View')),
        SubmenuButton(menuChildren: [
          item('Keyboard shortcuts', () => showKeyBindings(context)),
          item('Tutorial', () => _addDoc(_newDoc(tutorialText))),
          item('About', () => showInfo(context, 'Haruspex', 'A plain text editor built on Org mode.\nVersion $appVersion.')),
        ], child: const Text('Help')),
      ],
    );
  }

  /// Closes every tab (asking to save) to get back to the dashboard.
  Future<void> _showDashboard() async {
    for (final d in [...docs]) {
      final i = docs.indexOf(d);
      if (i < 0) continue;
      await closeTab(i);
      if (docs.contains(d)) return;
    }
  }

  Widget _tabBar(BuildContext context, OrgTheme t) {
    return Container(
      height: 24,
      decoration: BoxDecoration(color: t.panel, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < docs.length; i++) _tab(context, i, t),
            ],
          ),
        ),
        HoverBox(
          theme: t,
          onTap: newDocument,
          tooltip: vault == null ? 'New file' : 'New note',
          builder: (hot) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('+', style: TextStyle(color: hot ? Colors.black : t.accent)),
          ),
        ),
      ]),
    );
  }

  int _lastTabTap = -1;
  DateTime _lastTabTapTime = DateTime(0);

  /// A click selects the tab; a second click on the same tab renames it.
  void _tabTapped(int i) {
    final now = DateTime.now();
    final again = i == _lastTabTap && now.difference(_lastTabTapTime) < const Duration(milliseconds: 400);
    _lastTabTap = again ? -1 : i;
    _lastTabTapTime = now;
    _selectTab(i);
    if (again) renameDocument(docs[i]);
  }

  Future<void> _tabMenu(int i, Offset global) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox || i >= docs.length) return;
    final d = docs[i];
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(height: 24, value: 'rename', child: Text('Rename…')),
        PopupMenuItem(height: 24, value: 'close', child: Text('Close')),
        PopupMenuItem(height: 24, value: 'others', child: Text('Close other tabs')),
      ],
    );
    final at = docs.indexOf(d);
    if (choice == null || at < 0) return;
    switch (choice) {
      case 'rename':
        renameDocument(d);
      case 'close':
        closeTab(at);
      case 'others':
        for (final o in [...docs]) {
          if (identical(o, d)) continue;
          final k = docs.indexOf(o);
          if (k >= 0) await closeTab(k);
          if (docs.contains(o)) break;
        }
    }
  }

  Widget _tab(BuildContext context, int i, OrgTheme t) {
    final d = docs[i];
    final selected = i == current;
    return Tooltip(
      message: d.path ?? (d.scratch ? 'Scratch buffer, closes without saving' : 'Not saved yet'),
      child: GestureDetector(
        onTap: () => _tabTapped(i),
        onTertiaryTapUp: (_) => closeTab(i),
        onSecondaryTapUp: (e) => _tabMenu(i, e.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: selected ? t.background : t.panel,
              border: Border(
                top: BorderSide(color: selected ? t.accent : t.panel, width: 2),
                right: BorderSide(color: t.border),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                d.name,
                style: TextStyle(
                  color: d.scratch ? (selected ? t.levels[1] : t.tag) : (selected ? t.accent : t.faint),
                  fontStyle: d.scratch ? FontStyle.italic : null,
                ),
              ),
              if (d.dirty && !d.scratch) Text(' ●', style: TextStyle(color: t.accent)),
              const SizedBox(width: 6),
              HoverBox(
                theme: t,
                onTap: () => closeTab(i),
                tooltip: 'Close (Ctrl+W)',
                builder: (hot) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('×', style: TextStyle(color: hot ? Colors.black : t.faint)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Mode line, echo area and the find prompt
  // -------------------------------------------------------------------------

  Widget _modeLine(BuildContext context, OrgTheme t) {
    final d = doc;
    final v = vault;
    final style = TextStyle(color: t.text);
    final faint = TextStyle(color: t.faint);
    return Container(
      height: 24,
      decoration: BoxDecoration(color: t.panel, border: Border(top: BorderSide(color: t.border))),
      child: Row(children: [
        Container(width: 4, color: t.accent),
        const SizedBox(width: 8),
        if (d == null)
          Expanded(child: Text(v == null ? '*dashboard*' : '*dashboard*  ${v.name}', style: style))
        else ...[
          Text(d.dirty && !d.scratch ? '●' : '○', style: TextStyle(color: d.dirty && !d.scratch ? t.accent : t.faint)),
          const SizedBox(width: 8),
          Flexible(
            child: Tooltip(
              message: d.path ?? 'Not saved yet',
              child: Text(
                d.path != null && v != null && v.contains(d.path!) ? stripNoteExtension(v.relative(d.path!)) : d.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.bright, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 16),
          ListenableBuilder(
            listenable: d.controller,
            builder: (context, _) {
              final c = d.controller;
              final a = c.analysis;
              final sel = c.selection;
              final off = sel.isValid ? sel.extentOffset.clamp(0, a.text.length) : 0;
              final line = a.lineOfOffset(off);
              final col = off - a.lineStarts[line];
              return Text('${line + 1}:$col', style: faint);
            },
          ),
          const Spacer(),
          if (v != null) ...[Text(v.name, style: faint), const SizedBox(width: 16)],
          ListenableBuilder(
            listenable: d.controller,
            builder: (context, _) => Text('${_words(d.controller.analysis)}w', style: faint),
          ),
          const SizedBox(width: 16),
          Text(d.usesCrlf ? 'CRLF' : 'LF', style: faint),
          const SizedBox(width: 8),
          Text(d.encodingName, style: faint),
          const SizedBox(width: 16),
          if (d.scratch) ...[Text('scratch', style: TextStyle(color: t.tag)), const SizedBox(width: 10)],
          Text('Org', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
        ],
      ]),
    );
  }

  Widget _echoArea(OrgTheme t) {
    return Container(
      height: 22,
      color: t.background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: _prefix
          ? Text('C-c-', style: TextStyle(color: t.accent))
          : Text(_message ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text)),
    );
  }

  Widget _findBar(BuildContext context, OrgTheme t) {
    Widget button(String label, String tip, VoidCallback onTap, {bool on = false}) => HoverBox(
          theme: t,
          onTap: onTap,
          tooltip: tip,
          builder: (hot) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(label, style: TextStyle(color: hot ? Colors.black : (on ? t.accent : t.faint))),
          ),
        );

    Widget field(TextEditingController ctrl, {FocusNode? focus, ValueChanged<String>? onChanged, required ValueChanged<String> onSubmitted}) {
      return Expanded(
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          style: TextStyle(color: t.text),
          decoration: minibufferDecoration,
          onChanged: onChanged,
          onEditingComplete: () {},
          onSubmitted: onSubmitted,
        ),
      );
    }

    void replaceOne() => editor?.replaceCurrent(_findCtrl.text, _replaceCtrl.text, caseSensitive: _caseSensitive);

    return Focus(
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _hideFind();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: t.background,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('I-search: ', style: TextStyle(color: t.accent)),
            field(
              _findCtrl,
              focus: _findFocus,
              onChanged: (_) => _find(forward: true, incremental: true),
              onSubmitted: (_) => _find(forward: true),
            ),
            Text(_findStatus, style: TextStyle(color: t.faint)),
            const SizedBox(width: 8),
            button('Aa', 'Match case', () => setState(() => _caseSensitive = !_caseSensitive), on: _caseSensitive),
            button('<', 'Previous', () => _find(forward: false)),
            button('>', 'Next (Enter)', () => _find(forward: true)),
            button('replace', 'Replace', () => setState(() => _replaceVisible = !_replaceVisible), on: _replaceVisible),
            button('×', 'Close (Esc)', _hideFind),
          ]),
          if (_replaceVisible)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Text('Replace with: ', style: TextStyle(color: t.accent)),
                field(_replaceCtrl, onSubmitted: (_) => replaceOne()),
                button('this', 'Replace this match', replaceOne),
                button('all', 'Replace all', () {
                  final n = editor?.replaceAll(_findCtrl.text, _replaceCtrl.text, caseSensitive: _caseSensitive) ?? 0;
                  showMessage('Replaced $n occurrence${n == 1 ? '' : 's'}');
                }),
              ]),
            ),
        ]),
      ),
    );
  }

  static final RegExp _wordRe = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  OrgAnalysis? _wordsFor;
  int _wordCount = 0;

  Timer? _wordTimer;

  /// Word count for the mode line. Big documents are counted after typing
  /// pauses instead of on every key.
  int _words(OrgAnalysis a) {
    if (identical(_wordsFor, a)) return _wordCount;
    if (a.text.length < 200000 || _wordsFor == null) {
      _wordsFor = a;
      _wordCount = _wordRe.allMatches(a.text).length;
      return _wordCount;
    }
    _wordTimer?.cancel();
    _wordTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final latest = doc?.controller.analysis;
      if (latest == null) return;
      setState(() {
        _wordsFor = latest;
        _wordCount = _wordRe.allMatches(latest.text).length;
      });
    });
    return _wordCount;
  }
}
