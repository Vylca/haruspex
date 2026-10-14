import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Family names of the fonts in [dirs] (and their subfolders), read from the
/// `name` table of each TrueType or OpenType file. Used where fontconfig's
/// fc-list is not available, such as macOS.
Set<String> fontFamiliesIn(List<String> dirs) {
  final out = <String>{};
  for (final path in dirs) {
    final dir = Directory(path);
    if (!dir.existsSync()) continue;
    List<FileSystemEntity> files;
    try {
      files = dir.listSync(recursive: true, followLinks: false);
    } catch (_) {
      continue;
    }
    for (final f in files) {
      if (f is! File) continue;
      final lower = f.path.toLowerCase();
      if (!(lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc') || lower.endsWith('.otc'))) {
        continue;
      }
      if (f.uri.pathSegments.last.startsWith('.')) continue;
      try {
        // Names starting with a dot are system fonts hidden from users.
        out.addAll(fontFamilies(f).where((n) => !n.startsWith('.')));
      } catch (_) {
        // Not a font we can read.
      }
    }
  }
  return out;
}

/// Family names in one font file (several for a collection).
List<String> fontFamilies(File file) {
  final raf = file.openSync();
  try {
    Uint8List read(int at, int n) {
      raf.setPositionSync(at);
      return raf.readSync(n);
    }

    final head = read(0, 12);
    if (head.length < 12) return const [];
    final bd = ByteData.sublistView(head);
    final offsets = <int>[];
    if (ascii.decode(head.sublist(0, 4), allowInvalid: true) == 'ttcf') {
      final n = bd.getUint32(8);
      final table = ByteData.sublistView(read(12, 4 * (n > 64 ? 64 : n)));
      for (var i = 0; i + 4 <= table.lengthInBytes; i += 4) {
        offsets.add(table.getUint32(i));
      }
    } else {
      offsets.add(0);
    }
    final names = <String>[];
    for (final off in offsets) {
      final name = _familyAt(read, off);
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names;
  } finally {
    raf.closeSync();
  }
}

String? _familyAt(Uint8List Function(int at, int n) read, int fontOffset) {
  final dir = ByteData.sublistView(read(fontOffset, 12));
  if (dir.lengthInBytes < 12) return null;
  final numTables = dir.getUint16(4);
  final records = ByteData.sublistView(read(fontOffset + 12, numTables * 16));
  int? nameOffset;
  for (var i = 0; i + 16 <= records.lengthInBytes; i += 16) {
    if (records.getUint32(i) == 0x6E616D65) {
      // 'name'
      nameOffset = records.getUint32(i + 8);
      break;
    }
  }
  if (nameOffset == null) return null;
  final header = ByteData.sublistView(read(nameOffset, 6));
  if (header.lengthInBytes < 6) return null;
  final count = header.getUint16(2);
  final stringsAt = nameOffset + header.getUint16(4);
  final recs = ByteData.sublistView(read(nameOffset + 6, count * 12));
  // The typographic family (16) when there is one, else the family (1);
  // English names first.
  String? best;
  var bestScore = -1;
  for (var i = 0; i + 12 <= recs.lengthInBytes; i += 12) {
    final platform = recs.getUint16(i);
    final encoding = recs.getUint16(i + 2);
    final language = recs.getUint16(i + 4);
    final nameId = recs.getUint16(i + 6);
    final length = recs.getUint16(i + 8);
    final offset = recs.getUint16(i + 10);
    if (nameId != 1 && nameId != 16) continue;
    final unicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
    final roman = platform == 1 && encoding == 0;
    if (!unicode && !roman) continue;
    final english = (platform == 3 && language == 0x409) || (platform == 1 && language == 0) || platform == 0;
    final score = (nameId == 16 ? 4 : 0) + (english ? 2 : 0) + (unicode ? 1 : 0);
    if (score <= bestScore) continue;
    final bytes = read(stringsAt + offset, length);
    String text;
    if (unicode) {
      final units = <int>[];
      for (var j = 0; j + 1 < bytes.length; j += 2) {
        units.add(bytes[j] << 8 | bytes[j + 1]);
      }
      text = String.fromCharCodes(units);
    } else {
      text = latin1.decode(bytes);
    }
    text = text.trim();
    if (text.isEmpty) continue;
    best = text;
    bestScore = score;
  }
  return best;
}
