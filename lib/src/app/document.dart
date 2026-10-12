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

  String _savedText;
  bool _dirty = false;

  bool get dirty => _dirty;

  String get name {
    final p = path;
    if (p == null) return 'untitled';
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

  static Future<OrgDocument> load(String path, OrgHighlighter highlighter) async {
    final bytes = await File(path).readAsBytes();
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final crlf = text.contains('\r\n');
    if (crlf) text = text.replaceAll('\r\n', '\n');
    final doc = OrgDocument(highlighter: highlighter, text: text, path: path)..usesCrlf = crlf;
    doc.controller.selection = const TextSelection.collapsed(offset: 0);
    return doc;
  }

  Future<void> saveTo(String target) async {
    var text = controller.text;
    final saved = text;
    if (usesCrlf) text = text.replaceAll('\n', '\r\n');
    await File(target).writeAsString(text, flush: true);
    path = target;
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
