import 'package:flutter/material.dart';

import '../app/document.dart';
import '../editor/highlighter.dart';
import '../editor/org_theme.dart';
import '../org/agenda.dart' show plainTitle;
import 'pixel_widgets.dart';

/// Sidebar listing every heading of the document.
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key, required this.doc, required this.theme, required this.onJump});

  final OrgDocument doc;
  final OrgTheme theme;
  final void Function(int line) onJump;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return ListenableBuilder(
      listenable: doc.controller,
      builder: (context, _) {
        final a = doc.controller.analysis;
        final caretLine = doc.controller.selection.isValid
            ? a.lineOfOffset(doc.controller.selection.extentOffset.clamp(0, a.text.length))
            : -1;
        final current = caretLine < 0 ? null : a.headingAtOrAbove(caretLine);
        final title = a.keywords['TITLE'];
        return ColoredBox(
          color: t.panel,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
              child: Text(
                ((title == null || title.isEmpty) ? doc.name : title).toUpperCase(),
                style: TextStyle(color: t.accent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 2, bottom: 24),
                children: [
                  if (a.headingLines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('No headings', style: TextStyle(color: t.faint)),
                    ),
                  for (final h in a.headingLines)
                    _row(a.headingInfo(h)!.level, a.headingInfo(h)!.keyword, plainTitle(a.headingInfo(h)!.title(a.lines[h])),
                        h, h == current, a.todo.isDone(a.headingInfo(h)!.keyword)),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _row(int level, String? keyword, String title, int line, bool selected, bool done) {
    final t = theme;
    final bullets = OrgHighlighter.headlineBullets;
    return HoverBox(
      theme: t,
      selected: selected,
      onTap: () => onJump(line),
      builder: (hot) => Padding(
        padding: EdgeInsets.fromLTRB(8.0 + 16.0 * (level - 1), 0, 8, 0),
        child: Row(children: [
          Text('${bullets[(level - 1) % bullets.length]} ', style: TextStyle(color: hot ? Colors.black : t.level(level))),
          if (keyword != null) ...[
            Text('$keyword ', style: TextStyle(color: hot ? Colors.black : (done ? t.done : t.todo))),
          ],
          Expanded(
            child: Text(
              title.isEmpty ? '(untitled)' : title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: hot ? Colors.black : (done ? t.faint : t.level(level))),
            ),
          ),
        ]),
      ),
    );
  }
}
