/// Hunspell through dart:ffi: load a dictionary, check words, get
/// suggestions.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

final class _Handle extends Opaque {}

typedef _CreateN = Pointer<_Handle> Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _DestroyN = Void Function(Pointer<_Handle>);
typedef _DestroyD = void Function(Pointer<_Handle>);
typedef _WordN = Int32 Function(Pointer<_Handle>, Pointer<Uint8>);
typedef _WordD = int Function(Pointer<_Handle>, Pointer<Uint8>);
typedef _EncodingN = Pointer<Uint8> Function(Pointer<_Handle>);
typedef _SuggestN = Int32 Function(Pointer<_Handle>, Pointer<Pointer<Pointer<Uint8>>>, Pointer<Uint8>);
typedef _SuggestD = int Function(Pointer<_Handle>, Pointer<Pointer<Pointer<Uint8>>>, Pointer<Uint8>);
typedef _FreeListN = Void Function(Pointer<_Handle>, Pointer<Pointer<Pointer<Uint8>>>, Int32);
typedef _FreeListD = void Function(Pointer<_Handle>, Pointer<Pointer<Pointer<Uint8>>>, int);
typedef _MallocN = Pointer<Void> Function(IntPtr);
typedef _MallocD = Pointer<Void> Function(int);
typedef _FreeN = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);

class _Api {
  _Api(DynamicLibrary lib)
      : create = lib.lookupFunction<_CreateN, _CreateN>('Hunspell_create'),
        destroy = lib.lookupFunction<_DestroyN, _DestroyD>('Hunspell_destroy'),
        spell = lib.lookupFunction<_WordN, _WordD>('Hunspell_spell'),
        add = lib.lookupFunction<_WordN, _WordD>('Hunspell_add'),
        remove = lib.lookupFunction<_WordN, _WordD>('Hunspell_remove'),
        encoding = lib.lookupFunction<_EncodingN, _EncodingN>('Hunspell_get_dic_encoding'),
        suggest = lib.lookupFunction<_SuggestN, _SuggestD>('Hunspell_suggest'),
        freeList = lib.lookupFunction<_FreeListN, _FreeListD>('Hunspell_free_list'),
        malloc = DynamicLibrary.process().lookupFunction<_MallocN, _MallocD>('malloc'),
        free = DynamicLibrary.process().lookupFunction<_FreeN, _FreeD>('free');

  final _CreateN create;
  final _DestroyD destroy;
  final _WordD spell;
  final _WordD add;
  final _WordD remove;
  final _EncodingN encoding;
  final _SuggestD suggest;
  final _FreeListD freeList;
  final _MallocD malloc;
  final _FreeD free;
}

/// A loaded Hunspell dictionary. Not safe to use from two threads at once.
class Hunspell {
  Hunspell._(this._h, this._codec);

  /// Where the library is, when it is not next to the app (tests). Set it in
  /// every isolate that uses Hunspell.
  static String? libraryPath;

  static _Api? _api;
  static bool _tried = false;

  static _Api? get _bindings {
    if (_tried) return _api;
    _tried = true;
    try {
      final name = Platform.isWindows
          ? 'haruspex_hunspell.dll'
          : Platform.isMacOS || Platform.isIOS
              ? 'haruspex_hunspell.framework/haruspex_hunspell'
              : 'libharuspex_hunspell.so';
      _api = _Api(DynamicLibrary.open(libraryPath ?? name));
    } catch (_) {
      _api = null;
    }
    return _api;
  }

  /// Whether the native library could be loaded.
  static bool get available => _bindings != null;

  /// Loads the dictionary made of [affPath] and [dicPath], or returns null
  /// when the library or the files are missing. Takes from a few to a few
  /// hundred milliseconds: call it outside the UI isolate.
  static Hunspell? open(String affPath, String dicPath) {
    final api = _bindings;
    if (api == null) return null;
    if (!File(affPath).existsSync() || !File(dicPath).existsSync()) return null;
    final aff = _cString(api, utf8.encode(affPath));
    final dic = _cString(api, utf8.encode(dicPath));
    try {
      final h = api.create(aff, dic);
      if (h == nullptr) return null;
      return Hunspell._(h, _codecFor(api, h));
    } finally {
      api.free(aff.cast());
      api.free(dic.cast());
    }
  }

  /// A dictionary opened by [open], possibly in another isolate.
  static Hunspell? fromAddress(int address) {
    final api = _bindings;
    if (api == null || address == 0) return null;
    final h = Pointer<_Handle>.fromAddress(address);
    return Hunspell._(h, _codecFor(api, h));
  }

  final Pointer<_Handle> _h;
  final Encoding? _codec;
  bool _disposed = false;

  /// Native address, to hand the dictionary to another isolate.
  int get address => _h.address;

  /// Whether the dictionary's encoding is one Dart can write (UTF-8 or
  /// ISO 8859-1).
  bool get supported => _codec != null;

  static Encoding? _codecFor(_Api api, Pointer<_Handle> h) {
    final p = api.encoding(h);
    if (p == nullptr) return utf8;
    final name = _readCString(p, latin1).toUpperCase().replaceAll('-', '').replaceAll('_', '');
    if (name == 'UTF8') return utf8;
    if (name == 'ISO88591' || name == 'LATIN1') return latin1;
    return null;
  }

  static Pointer<Uint8> _cString(_Api api, List<int> bytes) {
    final p = api.malloc(bytes.length + 1).cast<Uint8>();
    final view = p.asTypedList(bytes.length + 1);
    view.setAll(0, bytes);
    view[bytes.length] = 0;
    return p;
  }

  static String _readCString(Pointer<Uint8> p, Encoding codec) {
    var n = 0;
    while (p[n] != 0) {
      n++;
    }
    return codec.decode(p.asTypedList(n));
  }

  List<int>? _encode(String word) {
    try {
      return _codec?.encode(word);
    } catch (_) {
      return null;
    }
  }

  /// Whether [word] is spelled correctly. Words the dictionary's encoding
  /// cannot hold count as correct.
  bool spell(String word) {
    if (_disposed) return true;
    final api = _bindings!;
    final bytes = _encode(word);
    if (bytes == null) return true;
    final p = _cString(api, bytes);
    try {
      return api.spell(_h, p) != 0;
    } finally {
      api.free(p.cast());
    }
  }

  /// Corrections for [word], best first.
  List<String> suggest(String word) {
    if (_disposed) return const [];
    final api = _bindings!;
    final bytes = _encode(word);
    if (bytes == null) return const [];
    final p = _cString(api, bytes);
    final list = api.malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Pointer<Uint8>>>();
    list.value = nullptr;
    try {
      final n = api.suggest(_h, list, p);
      final out = <String>[];
      for (var i = 0; i < n; i++) {
        out.add(_readCString(list.value[i], _codec!));
      }
      if (n > 0) api.freeList(_h, list, n);
      return out;
    } finally {
      api.free(p.cast());
      api.free(list.cast());
    }
  }

  /// Accepts [word] from now on (not saved by Hunspell).
  void add(String word) => _call(word, _bindings!.add);

  /// Stops accepting a word added with [add].
  void remove(String word) => _call(word, _bindings!.remove);

  void _call(String word, _WordD f) {
    if (_disposed) return;
    final bytes = _encode(word);
    if (bytes == null) return;
    final api = _bindings!;
    final p = _cString(api, bytes);
    try {
      f(_h, p);
    } finally {
      api.free(p.cast());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings!.destroy(_h);
  }
}
