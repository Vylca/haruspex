import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/document.dart';
import '../app/settings.dart';
import '../app/vault.dart';
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
import 'outline_panel.dart';
import 'quick_switcher.dart';
import 'settings_dialog.dart';
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
    for (final d in docs) {
      d.dispose();
    }
    vault?.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _findFocus.dispose();
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
    if (docs.isEmpty && vault == null) {
      if (!settings.tutorialShown) {
        _addDoc(_newDoc(tutorialText));
        settings.update((s) => s.tutorialShown = true);
      } else {
        _addDoc(_newDoc(''));
      }
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
      doc?.focusNode.requestFocus();
    });
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
      if (cur != null && cur.path == null && !cur.dirty && cur.controller.text.isEmpty) {
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

  Future<bool> _confirmClose(OrgDocument d) async {
    if (!d.dirty) return true;
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
      docs.removeAt(i);
      if (current >= docs.length) current = docs.length - 1;
      if (current < 0) current = 0;
    });
    _disposeDoc(d);
    if (docs.isEmpty && vault == null) newDocument();
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
        case TreeAction.rename:
          final oldName = target.isDir ? target.name : stripNoteExtension(target.name);
          final name = await showTextPrompt(context, title: 'Rename', initial: oldName, label: 'Name');
          if (name == null || name.isEmpty || name == oldName) return;
          final newPath = await v.rename(target.path, name);
          setState(() {
            for (final d in docs) {
              final p = d.path;
              if (p == null) continue;
              if (p == target.path) {
                d.path = newPath;
              } else if (target.isDir && p.startsWith('${target.path}${Platform.pathSeparator}')) {
                d.path = newPath + p.substring(target.path.length);
              }
            }
          });
          _saveVaultState();
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
    final theme = settings.orgTheme(Theme.of(context).brightness);
    final item = await Navigator.of(context).push<AgendaItem>(MaterialPageRoute(
      builder: (_) => AgendaPage(
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
    final brightness = Theme.of(context).brightness;
    final orgTheme = settings.orgTheme(brightness);
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

    final d = doc;
    final v = vault;
    return Scaffold(
      backgroundColor: orgTheme.background,
      body: CallbackShortcuts(
        bindings: _shortcuts,
        child: Column(children: [
          _menuBar(context),
          _tabBar(context, orgTheme),
          Expanded(
            child: Row(children: [
              if (v != null && settings.showFiles) ...[
                SizedBox(
                  width: 260,
                  child: FileTreePanel(
                    vault: v,
                    theme: orgTheme,
                    activePath: d?.path,
                    onOpen: (p) => openPath(p),
                    onAction: _treeAction,
                  ),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: docs.isEmpty
                    ? _emptyState(context, orgTheme)
                    : IndexedStack(
                        index: current.clamp(0, docs.length - 1),
                        children: [
                          for (final x in docs)
                            OrgEditor(key: _editorKeys[x.id], doc: x, host: this, settings: settings),
                        ],
                      ),
              ),
              if (settings.showOutline && d != null) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 270,
                  child: OutlinePanel(
                    doc: d,
                    theme: orgTheme,
                    onJump: (line) => editor?.jumpToLine(line),
                  ),
                ),
              ],
            ]),
          ),
          if (_findVisible) _findBar(context),
          _statusBar(context, orgTheme),
        ]),
      ),
    );
  }

  Widget _emptyState(BuildContext context, OrgTheme t) {
    final v = vault;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(v == null ? 'No file open' : v.name, style: TextStyle(fontSize: 20, color: t.faint)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          FilledButton.tonal(onPressed: newDocument, child: const Text('New note  (Ctrl+N)')),
          if (v != null) FilledButton.tonal(onPressed: quickSwitch, child: const Text('Find note  (Ctrl+P)')),
          if (v == null) FilledButton.tonal(onPressed: openVaultDialog, child: const Text('Open folder…')),
          FilledButton.tonal(onPressed: openDialog, child: const Text('Open file…  (Ctrl+O)')),
        ]),
      ]),
    );
  }

  Widget _menuBar(BuildContext context) {
    MenuItemButton item(String label, VoidCallback? onPressed, {MenuSerializableShortcut? shortcut, String? hint}) {
      return MenuItemButton(
        onPressed: onPressed,
        shortcut: shortcut,
        trailingIcon: hint == null
            ? null
            : Text(hint, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        child: Text(label),
      );
    }

    final hasDoc = doc != null;
    VoidCallback? cmd(String id) => hasDoc ? () => _command(id) : null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(children: [
        Expanded(
          child: MenuBar(
            style: const MenuStyle(
              elevation: WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            ),
            children: [
              SubmenuButton(menuChildren: [
                item(vault == null ? 'New file' : 'New note', newDocument,
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true)),
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
                item('Agenda', hasDoc ? _openAgenda : null, hint: 'C-c a'),
              ], child: const Text('Org')),
              SubmenuButton(menuChildren: [
                item(settings.showFiles ? 'Hide files' : 'Show files',
                    vault == null ? null : () => settings.update((s) => s.showFiles = !s.showFiles),
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true)),
                item(settings.showOutline ? 'Hide outline' : 'Show outline',
                    () => settings.update((s) => s.showOutline = !s.showOutline),
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true)),
                item('Zoom in', () => _zoom(1), shortcut: const SingleActivator(LogicalKeyboardKey.equal, control: true)),
                item('Zoom out', () => _zoom(-1), shortcut: const SingleActivator(LogicalKeyboardKey.minus, control: true)),
                item('Reset zoom', () => _zoom(0), shortcut: const SingleActivator(LogicalKeyboardKey.digit0, control: true)),
                const Divider(height: 1),
                item('Settings…', () => showSettingsDialog(context, settings)),
              ], child: const Text('View')),
              SubmenuButton(menuChildren: [
                item('Keyboard shortcuts', () => showKeyBindings(context)),
                item('Tutorial', () => _addDoc(_newDoc(tutorialText))),
                item('About', () => showInfo(context, 'OrgPad', 'A plain text editor built on Org mode.\nProof of concept, version 0.1.')),
              ], child: const Text('Help')),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _tabBar(BuildContext context, OrgTheme t) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      color: scheme.surfaceContainer,
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < docs.length; i++) _tab(context, i, t),
            ],
          ),
        ),
        IconButton(
          tooltip: 'New note',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 18),
          onPressed: newDocument,
        ),
        IconButton(
          tooltip: vault == null ? 'Open folder' : 'Files',
          visualDensity: VisualDensity.compact,
          icon: Icon(vault == null ? Icons.folder_open_outlined : Icons.folder_outlined, size: 18),
          onPressed: vault == null ? openVaultDialog : () => settings.update((s) => s.showFiles = !s.showFiles),
        ),
        IconButton(
          tooltip: 'Agenda',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.calendar_month, size: 18),
          onPressed: docs.isEmpty ? null : _openAgenda,
        ),
        IconButton(
          tooltip: 'Outline',
          visualDensity: VisualDensity.compact,
          icon: Icon(settings.showOutline ? Icons.view_sidebar : Icons.view_sidebar_outlined, size: 18),
          onPressed: () => settings.update((s) => s.showOutline = !s.showOutline),
        ),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _tab(BuildContext context, int i, OrgTheme t) {
    final d = docs[i];
    final selected = i == current;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: d.path ?? 'Not saved yet',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => _selectTab(i),
        child: Container(
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(
            color: selected ? t.background : Colors.transparent,
            border: Border(
              top: BorderSide(color: selected ? t.accent : Colors.transparent, width: 2),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              d.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? t.text : scheme.onSurfaceVariant,
              ),
            ),
            if (d.dirty) Text('  •', style: TextStyle(color: t.accent, fontWeight: FontWeight.w900)),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => closeTab(i),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _findBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _hideFind();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: scheme.surfaceContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _findCtrl,
                focusNode: _findFocus,
                decoration: const InputDecoration(isDense: true, hintText: 'Find', border: OutlineInputBorder()),
                onChanged: (_) => _find(forward: true, incremental: true),
                onEditingComplete: () {},
                onSubmitted: (_) => _find(forward: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: Text(_findStatus, style: TextStyle(color: scheme.outline, fontSize: 12))),
            IconButton(
              tooltip: 'Match case',
              isSelected: _caseSensitive,
              icon: const Icon(Icons.text_fields),
              onPressed: () => setState(() => _caseSensitive = !_caseSensitive),
            ),
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => _find(forward: false),
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => _find(forward: true),
            ),
            IconButton(
              tooltip: 'Replace',
              icon: const Icon(Icons.find_replace),
              onPressed: () => setState(() => _replaceVisible = !_replaceVisible),
            ),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: _hideFind),
          ]),
          if (_replaceVisible)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _replaceCtrl,
                    decoration: const InputDecoration(isDense: true, hintText: 'Replace with', border: OutlineInputBorder()),
                    onEditingComplete: () {},
                    onSubmitted: (_) => editor?.replaceCurrent(_findCtrl.text, _replaceCtrl.text, caseSensitive: _caseSensitive),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => editor?.replaceCurrent(_findCtrl.text, _replaceCtrl.text, caseSensitive: _caseSensitive),
                  child: const Text('Replace'),
                ),
                TextButton(
                  onPressed: () {
                    final n = editor?.replaceAll(_findCtrl.text, _replaceCtrl.text, caseSensitive: _caseSensitive) ?? 0;
                    showMessage('Replaced $n occurrence${n == 1 ? '' : 's'}');
                  },
                  child: const Text('Replace all'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _statusBar(BuildContext context, OrgTheme t) {
    final scheme = Theme.of(context).colorScheme;
    final d = doc;
    final style = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Container(
      height: 26,
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        if (_prefix)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: t.markerBg, borderRadius: BorderRadius.circular(4)),
            child: Text('C-c –', style: style.copyWith(color: t.markerFg, fontWeight: FontWeight.w700)),
          ),
        Expanded(
          child: Text(
            _message ?? (d?.path ?? (d == null ? '' : 'Not saved yet')),
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (d != null)
          ListenableBuilder(
            listenable: d.controller,
            builder: (context, _) {
              final c = d.controller;
              final a = c.analysis;
              final sel = c.selection;
              final off = sel.isValid ? sel.extentOffset.clamp(0, a.text.length) : 0;
              final line = a.lineOfOffset(off);
              final col = off - a.lineStarts[line];
              return Text('Ln ${line + 1}, Col ${col + 1}   ${_words(a)} words', style: style);
            },
          ),
      ]),
    );
  }

  static final RegExp _wordRe = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  OrgAnalysis? _wordsFor;
  int _wordCount = 0;

  int _words(OrgAnalysis a) {
    if (!identical(_wordsFor, a)) {
      _wordsFor = a;
      _wordCount = _wordRe.allMatches(a.text).length;
    }
    return _wordCount;
  }
}
