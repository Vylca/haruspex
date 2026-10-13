import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../editor/highlighter.dart';
import '../editor/org_controller.dart';

/// One open file (or an untitled buffer).
class OrgDocument extends ChangeNotifier {
  OrgDocument({required OrgHighlighter highlighter, String text = '', this.path})
      : controller = OrgController(text: text, highlighter: highlighter),
        _savedText = text,
        id = _nextId++ {
    controller.addListener(_onChanged);
  }

  static int _nextId = 1;

  final int id;
  String? path;
  final OrgController controller;
  final FocusNode focusNode = FocusNode(debugLabel: 'org-editor');
  final ScrollController scroll = ScrollController();
  bool usesCrlf = false;

  /// A scratch buffer: a throwaway note that is not a file and closes
  /// without asking to save.
  bool scratch = false;

  /// Name shown for a buffer that is not saved to a file.
  String? title;

  String _savedText;
  bool _dirty = false;

  bool get dirty => _dirty;

  String get name {
    final p = path;
    if (p == null) return title ?? 'untitled';
    final parts = p.split(Platform.pathSeparator);
    return parts.isEmpty ? p : parts.last;
  }

  String? get directory {
    final p = path;
    if (p == null) return null;
    final i = p.lastIndexOf(Platform.pathSeparator);
    return i <= 0 ? null : p.substring(0, i);
  }

  void _onChanged() {
    final t = controller.text;
    final d = !identical(t, _savedText) && t != _savedText;
    if (d != _dirty) {
      _dirty = d;
      notifyListeners();
    }
  }

  /// The file was not valid UTF-8 and is read and written as Latin-1, so
  /// its bytes survive a save.
  bool latin1 = false;

  /// The file started with a byte order mark, written back on save.
  bool bom = false;

  /// Modification time and size of the file when it was last read or
  /// written, to notice changes made by other programs.
  DateTime? diskModified;
  int? diskSize;

  String get encodingName => latin1 ? 'LATIN-1' : 'UTF-8';

  static Future<OrgDocument> load(String path, OrgHighlighter highlighter) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    String text;
    var isLatin1 = false;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = const Latin1Codec().decode(bytes);
      isLatin1 = true;
    }
    final hasBom = text.startsWith('\ufeff');
    if (hasBom) text = text.substring(1);
    final crlf = text.contains('\r\n');
    if (crlf) text = text.replaceAll('\r\n', '\n');
    final doc = OrgDocument(highlighter: highlighter, text: text, path: path)
      ..usesCrlf = crlf
      ..latin1 = isLatin1
      ..bom = hasBom;
    doc.controller.selection = const TextSelection.collapsed(offset: 0);
    await doc._stamp();
    return doc;
  }

  Future<void> _stamp() async {
    final p = path;
    if (p == null) return;
    try {
      final st = await File(p).stat();
      diskModified = st.modified;
      diskSize = st.size;
    } catch (_) {
      diskModified = null;
      diskSize = null;
    }
  }

  /// Whether another program changed (or removed) the file since it was
  /// last read or written here.
  Future<bool> changedOnDisk() async {
    final p = path;
    final m = diskModified;
    if (p == null || m == null) return false;
    try {
      final st = await File(p).stat();
      if (st.type == FileSystemEntityType.notFound) return false;
      return st.modified != m || st.size != diskSize;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveTo(String target) async {
    var text = controller.text;
    final saved = text;
    if (usesCrlf) text = text.replaceAll('\n', '\r\n');
    if (bom) text = '\ufeff$text';
    List<int> bytes;
    if (latin1) {
      try {
        bytes = const Latin1Codec().encode(text);
      } on ArgumentError {
        // Text that Latin-1 cannot hold: switch the file to UTF-8.
        latin1 = false;
        bytes = utf8.encode(text);
      }
    } else {
      bytes = utf8.encode(text);
    }
    await File(target).writeAsBytes(bytes, flush: true);
    path = target;
    await _stamp();
    scratch = false;
    title = null;
    _savedText = saved;
    _dirty = false;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    controller.dispose();
    focusNode.dispose();
    scroll.dispose();
    super.dispose();
  }
}
