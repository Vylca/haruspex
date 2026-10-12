import 'package:flutter/material.dart';

import '../app/document.dart';
import '../editor/org_theme.dart';
import '../org/agenda.dart' show plainTitle;

/// Sidebar listing every heading of the document.
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key, required this.doc, required this.theme, required this.onJump});

  final OrgDocument doc;
  final OrgTheme theme;
  final void Function(int line) onJump;

  @override
  Widget build(BuildContext context) {
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
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  (title == null || title.isEmpty) ? doc.name : title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (a.headingLines.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No headings', style: TextStyle(color: theme.faint)),
                ),
              for (final h in a.headingLines)
                _row(context, a.headingInfo(h)!.level, a.headingInfo(h)!.keyword,
                    plainTitle(a.headingInfo(h)!.title(a.lines[h])), h, h == current, a.todo.isDone(a.headingInfo(h)!.keyword)),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, int level, String? keyword, String title, int line, bool selected, bool done) {
    return InkWell(
      onTap: () => onJump(line),
      child: Container(
        color: selected ? theme.markerBg : null,
        padding: EdgeInsets.fromLTRB(12.0 + 14.0 * (level - 1), 5, 12, 5),
        child: Row(children: [
          if (keyword != null) ...[
            Text(keyword, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: done ? theme.done : theme.todo)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title.isEmpty ? '(untitled)' : title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: done ? theme.faint : theme.level(level),
                fontWeight: level == 1 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
