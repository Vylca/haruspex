/// Org tables: parsing, alignment and row/column editing.
library;

import 'syntax.dart';

final RegExp _numberRe = RegExp(r'^[<>]?[-+]?[0-9.,]*[0-9][0-9.,eE]*%?$');

class TableCaret {
  TableCaret(this.row, this.cell, this.offset);
  int row;
  int cell;
  int offset;
}

class OrgTable {
  OrgTable(this.startLine, this.endLine, this.indent, this.rows);

  /// First line of the table (inclusive).
  final int startLine;

  /// Line after the table (exclusive), in the original document.
  final int endLine;
  final String indent;

  /// Rows; `null` marks a horizontal rule.
  final List<List<String>?> rows;

  static bool isTableLine(String line) => tableRe.hasMatch(line);

  static OrgTable? at(List<String> lines, int line) {
    if (line < 0 || line >= lines.length || !isTableLine(lines[line])) return null;
    var s = line, e = line;
    while (s > 0 && isTableLine(lines[s - 1])) {
      s--;
    }
    while (e + 1 < lines.length && isTableLine(lines[e + 1])) {
      e++;
    }
    final rows = <List<String>?>[];
    for (var i = s; i <= e; i++) {
      rows.add(parseRow(lines[i]));
    }
    return OrgTable(s, e + 1, leadingWhitespace(lines[s]), rows);
  }

  static List<String>? parseRow(String line) {
    if (tableRuleRe.hasMatch(line)) return null;
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  int get columnCount {
    var n = 0;
    for (final r in rows) {
      if (r != null && r.length > n) n = r.length;
    }
    return n == 0 ? 1 : n;
  }

  void normalize() {
    final n = columnCount;
    for (final r in rows) {
      if (r == null) continue;
      while (r.length < n) {
        r.add('');
      }
    }
  }

  List<int> widths() {
    final n = columnCount;
    final w = List<int>.filled(n, 1);
    for (final r in rows) {
      if (r == null) continue;
      for (var i = 0; i < r.length && i < n; i++) {
        final len = r[i].runes.length;
        if (len > w[i]) w[i] = len;
      }
    }
    return w;
  }

  List<bool> rightAligned() {
    final n = columnCount;
    final result = List<bool>.filled(n, false);
    for (var c = 0; c < n; c++) {
      var nums = 0, nonEmpty = 0;
      for (final r in rows) {
        if (r == null || c >= r.length || r[c].isEmpty) continue;
        nonEmpty++;
        if (_numberRe.hasMatch(r[c])) nums++;
      }
      result[c] = nonEmpty > 0 && nums * 2 > nonEmpty;
    }
    return result;
  }

  static String _pad(String s, int width, bool right) {
    final pad = width - s.runes.length;
    if (pad <= 0) return s;
    return right ? '${' ' * pad}$s' : '$s${' ' * pad}';
  }

  List<String> format() {
    normalize();
    final w = widths();
    final right = rightAligned();
    final out = <String>[];
    for (final r in rows) {
      if (r == null) {
        out.add('$indent|${w.map((x) => '-' * (x + 2)).join('+')}|');
      } else {
        final cells = <String>[];
        for (var i = 0; i < w.length; i++) {
          cells.add(_pad(i < r.length ? r[i] : '', w[i], right[i]));
        }
        out.add('$indent| ${cells.join(' | ')} |');
      }
    }
    return out;
  }

  /// Caret position (row, cell, offset in cell text) for a column in a line.
  TableCaret caretFor(String line, int row, int col) {
    final ind = leadingWhitespace(line).length;
    if (rows[row] == null) return TableCaret(row, 0, 0);
    var cell = -1;
    var cellStart = ind;
    for (var i = ind; i < line.length && i < col; i++) {
      if (line[i] == '|') {
        cell++;
        cellStart = i + 1;
      }
    }
    if (cell < 0) cell = 0;
    var contentStart = cellStart;
    while (contentStart < line.length && line[contentStart] == ' ') {
      contentStart++;
    }
    final off = col - contentStart;
    return TableCaret(row, cell, off < 0 ? 0 : off);
  }

  /// Column in a formatted row where the content of [cell] starts, given the
  /// widths. Right-aligned cells start after their padding.
  int columnOf(List<String> formatted, TableCaret c) {
    final line = formatted[c.row];
    if (rows[c.row] == null) return indent.length + 1;
    var pipes = -1;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '|') {
        pipes++;
        if (pipes == c.cell) {
          var s = i + 1;
          while (s < line.length && line[s] == ' ') {
            s++;
          }
          if (s >= line.length || line[s] == '|') {
            // Empty cell: place the caret one space after the pipe.
            return i + 2 <= line.length ? i + 2 : line.length;
          }
          final cellText = rows[c.row]![c.cell];
          final off = c.offset > cellText.length ? cellText.length : c.offset;
          return s + off;
        }
      }
    }
    return line.length;
  }
}

/// Result of a table operation: the document lines and the caret.
class TableResult {
  TableResult(this.lines, this.caretLine, this.caretCol);
  final List<String> lines;
  final int caretLine;
  final int caretCol;
}

enum TableOp {
  align,
  nextField,
  previousField,
  nextRow,
  moveRowUp,
  moveRowDown,
  moveColumnLeft,
  moveColumnRight,
  insertRowAbove,
  insertRowBelow,
  deleteRow,
  insertColumn,
  deleteColumn,
  insertHline,
}

TableResult? tableOperation(List<String> lines, int line, int col, TableOp op) {
  final t = OrgTable.at(lines, line);
  if (t == null) return null;
  t.normalize();
  final rowIdx = line - t.startLine;
  final caret = t.caretFor(lines[line], rowIdx, col);
  final n = t.columnCount;

  int? nextDataRow(int from) {
    for (var r = from + 1; r < t.rows.length; r++) {
      if (t.rows[r] != null) return r;
    }
    return null;
  }

  int? prevDataRow(int from) {
    for (var r = from - 1; r >= 0; r--) {
      if (t.rows[r] != null) return r;
    }
    return null;
  }

  List<String> emptyRow() => List<String>.filled(n, '', growable: true);

  switch (op) {
    case TableOp.align: {
        break;
    }
    case TableOp.nextField: {
        if (t.rows[caret.row] != null && caret.cell + 1 < n) {
          caret.cell++;
        } else {
          final r = nextDataRow(caret.row);
          if (r != null) {
            caret.row = r;
          } else {
            t.rows.add(emptyRow());
            caret.row = t.rows.length - 1;
          }
          caret.cell = 0;
        }
        caret.offset = 0;
    }
    case TableOp.previousField: {
        if (t.rows[caret.row] != null && caret.cell > 0) {
          caret.cell--;
        } else {
          final r = prevDataRow(caret.row);
          if (r != null) {
            caret.row = r;
            caret.cell = n - 1;
          }
        }
        caret.offset = 0;
    }
    case TableOp.nextRow: {
        final r = nextDataRow(caret.row);
        if (r != null && r == caret.row + 1) {
          caret.row = r;
        } else {
          t.rows.insert(caret.row + 1, emptyRow());
          caret.row = caret.row + 1;
        }
        caret.offset = 0;
    }
    case TableOp.moveRowUp: {
        if (caret.row == 0) return null;
        final tmp = t.rows[caret.row - 1];
        t.rows[caret.row - 1] = t.rows[caret.row];
        t.rows[caret.row] = tmp;
        caret.row--;
    }
    case TableOp.moveRowDown: {
        if (caret.row >= t.rows.length - 1) return null;
        final tmp = t.rows[caret.row + 1];
        t.rows[caret.row + 1] = t.rows[caret.row];
        t.rows[caret.row] = tmp;
        caret.row++;
    }
    case TableOp.moveColumnLeft:
    case TableOp.moveColumnRight: {
        final left = op == TableOp.moveColumnLeft;
        final other = left ? caret.cell - 1 : caret.cell + 1;
        if (t.rows[caret.row] == null || other < 0 || other >= n) return null;
        for (final r in t.rows) {
          if (r == null) continue;
          final tmp = r[other];
          r[other] = r[caret.cell];
          r[caret.cell] = tmp;
        }
        caret.cell = other;
    }
    case TableOp.insertRowAbove: {
        t.rows.insert(caret.row, emptyRow());
        caret.offset = 0;
    }
    case TableOp.insertRowBelow: {
        t.rows.insert(caret.row + 1, emptyRow());
        caret.row++;
        caret.offset = 0;
    }
    case TableOp.deleteRow: {
        if (t.rows.length <= 1) {
          // Deleting the only row removes the table.
          final out = [...lines]..removeRange(t.startLine, t.endLine);
          final l = t.startLine < out.length ? t.startLine : (out.isEmpty ? 0 : out.length - 1);
          if (out.isEmpty) out.add('');
          return TableResult(out, l, 0);
        }
        t.rows.removeAt(caret.row);
        if (caret.row >= t.rows.length) caret.row = t.rows.length - 1;
        caret.offset = 0;
    }
    case TableOp.insertColumn: {
        if (t.rows[caret.row] == null) return null;
        for (final r in t.rows) {
          r?.insert(caret.cell, '');
        }
        caret.offset = 0;
    }
    case TableOp.deleteColumn: {
        if (t.rows[caret.row] == null) return null;
        if (n <= 1) return null;
        for (final r in t.rows) {
          if (r != null && caret.cell < r.length) r.removeAt(caret.cell);
        }
        if (caret.cell >= n - 1) caret.cell = n - 2;
        caret.offset = 0;
    }
    case TableOp.insertHline: {
        t.rows.insert(caret.row + 1, null);
    }
  }
  if (t.rows[caret.row] == null) {
    final r = nextDataRow(caret.row) ?? prevDataRow(caret.row);
    if (r != null) {
      caret.row = r;
      caret.cell = 0;
      caret.offset = 0;
    }
  }
  final formatted = t.format();
  if (caret.cell >= t.columnCount) caret.cell = t.columnCount - 1;
  final out = <String>[
    ...lines.sublist(0, t.startLine),
    ...formatted,
    ...lines.sublist(t.endLine),
  ];
  final caretCol = t.columnOf(formatted, caret);
  return TableResult(out, t.startLine + caret.row, caretCol);
}

/// Converts a block of comma/tab separated lines, or creates an empty table.
List<String> newTable(String indent, int columns, int rows) {
  final w = 6;
  final row = '$indent|${List.filled(columns, ' ' * (w + 2)).join('|')}|';
  final header = '$indent|${List.filled(columns, '-' * (w + 2)).join('+')}|';
  return [row, header, for (var i = 0; i < rows; i++) row];
}
