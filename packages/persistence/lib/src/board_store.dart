import 'dart:convert';
import 'dart:io';

import 'package:local_board_core/local_board_core.dart';
import 'package:path/path.dart' as p;

/// Lightweight listing entry, so the home screen does not keep every board
/// in memory.
final class BoardSummary {
  const BoardSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.objectCount,
    required this.file,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final int objectCount;
  final File file;
}

/// Result of opening a board. [recoveredFrom] is set when the main file was
/// missing or damaged and a newer/older safe copy was used instead.
final class LoadedBoard {
  const LoadedBoard(this.document, {this.recoveredFrom});

  final BoardDocument document;
  final String? recoveredFrom;

  bool get wasRecovered => recoveredFrom != null;
}

class BoardNotFoundException implements Exception {
  const BoardNotFoundException(this.id);
  final String id;

  @override
  String toString() => 'Board $id not found';
}

/// Stores each board as `<boardId>.whiteboard` (plain versioned JSON) in
/// `<root>/boards`.
///
/// Crash safety (plan §12):
/// * saves write `<file>.tmp`, fsync, then atomically rename over the board;
/// * the previous good version is kept as `<file>.bak`;
/// * on open, the newest copy that parses wins (tmp → main → bak), so a crash
///   at any point during a save loses at most the edits since the last save.
final class BoardStore {
  BoardStore(this.root);

  static const extension = '.whiteboard';

  final Directory root;

  Directory get boardsDir => Directory(p.join(root.path, 'boards'));
  Directory get trashDir => Directory(p.join(root.path, 'trash'));
  File get _stateFile => File(p.join(root.path, 'state.json'));

  File fileFor(String id) => File(p.join(boardsDir.path, '$id$extension'));

  Future<void> init() async {
    await boardsDir.create(recursive: true);
  }

  // ---- listing ----

  Future<List<BoardSummary>> list() async {
    await init();
    final ids = <String>{};
    await for (final e in boardsDir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final match = RegExp(r'^([0-9a-zA-Z_-]+)\.whiteboard(\.tmp|\.bak)?$').firstMatch(name);
      if (match != null) ids.add(match.group(1)!);
    }
    final out = <BoardSummary>[];
    for (final id in ids) {
      try {
        final loaded = await open(id);
        final d = loaded.document;
        out.add(
          BoardSummary(id: d.id, title: d.title, updatedAt: d.updatedAt, objectCount: d.length, file: fileFor(id)),
        );
      } on Object {
        // Unreadable leftovers are skipped here; they are never deleted.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  // ---- create / open / save ----

  Future<BoardDocument> create({String title = 'Untitled board'}) async {
    final doc = BoardDocument.create(title: title);
    await save(doc);
    return doc;
  }

  Future<LoadedBoard> open(String id) async {
    final main = fileFor(id);
    final candidates = <(String, File)>[
      ('temporary save', File('${main.path}.tmp')),
      ('', main),
      ('backup', File('${main.path}.bak')),
    ];
    BoardDocument? best;
    String? bestSource;
    Object? lastError;
    for (final (label, file) in candidates) {
      if (!await file.exists()) continue;
      try {
        final doc = await _read(file);
        if (best == null || doc.updatedAt.isAfter(best.updatedAt)) {
          best = doc;
          bestSource = label;
        }
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (best == null) {
      if (lastError is UnsupportedSchemaException) throw lastError;
      if (lastError != null) throw FormatException('Board $id is damaged and has no usable copy: $lastError');
      throw BoardNotFoundException(id);
    }
    return LoadedBoard(best, recoveredFrom: (bestSource == null || bestSource.isEmpty) ? null : bestSource);
  }

  Future<void> save(BoardDocument doc) async {
    await init();
    final main = fileFor(doc.id);
    final tmp = File('${main.path}.tmp');
    final bak = File('${main.path}.bak');
    final bytes = utf8.encode(const JsonEncoder.withIndent(' ').convert(doc.toJson()));

    final raf = await tmp.open(mode: FileMode.writeOnly);
    try {
      await raf.writeFrom(bytes);
      await raf.flush(); // fsync: data is on disk before the rename publishes it
    } finally {
      await raf.close();
    }

    if (await main.exists()) {
      // Keep the last good version. copy (not rename) so `main` is never absent.
      await main.copy(bak.path);
    }
    await tmp.rename(main.path);
  }

  Future<BoardDocument> _read(File file) async {
    final text = await file.readAsString();
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) throw const FormatException('Board file is not a JSON object');
    return BoardDocument.fromJson(json);
  }

  // ---- delete / duplicate ----

  /// Moves every copy of the board to `trash/` — nothing is destroyed.
  Future<void> moveToTrash(String id) async {
    await trashDir.create(recursive: true);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final suffix in ['', '.tmp', '.bak']) {
      final f = File('${fileFor(id).path}$suffix');
      if (await f.exists()) {
        await f.rename(p.join(trashDir.path, '$id-$stamp${BoardStore.extension}$suffix'));
      }
    }
  }

  /// Boards that are in the trash and not on the board list, with when they
  /// were moved there (sync uses this to delete them elsewhere too).
  Future<Map<String, DateTime>> trashed() async {
    final out = <String, DateTime>{};
    if (!await trashDir.exists()) return out;
    await for (final e in trashDir.list()) {
      final m = RegExp(r'^([0-9a-zA-Z_-]+)-(\d+)\.whiteboard$').firstMatch(p.basename(e.path));
      if (m == null) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(2)!), isUtc: true);
      final prev = out[m.group(1)!];
      if (prev == null || at.isAfter(prev)) out[m.group(1)!] = at;
    }
    for (final id in out.keys.toList()) {
      if (await fileFor(id).exists()) out.remove(id);
    }
    return out;
  }

  /// The board as the bytes of a `.whiteboard` file.
  Future<List<int>> encode(BoardDocument doc) async => utf8.encode(const JsonEncoder.withIndent(' ').convert(doc.toJson()));

  Future<BoardDocument> duplicate(String id) async {
    final source = (await open(id)).document;
    final json = source.toJson()
      ..['boardId'] = newId()
      ..['title'] = '${source.title} (copy)'
      ..['createdAt'] = DateTime.now().toUtc().toIso8601String();
    final copy = BoardDocument.fromJson(json);
    await save(copy);
    return copy;
  }

  // ---- import / export (portable files, plan §14) ----

  Future<void> exportTo(BoardDocument doc, String path) async {
    final target = path.endsWith(extension) ? path : '$path$extension';
    await File(target).writeAsString(const JsonEncoder.withIndent(' ').convert(doc.toJson()), flush: true);
  }

  /// Imports a `.whiteboard` file. If a board with the same id already
  /// exists, the import gets a fresh id instead of overwriting it.
  Future<BoardDocument> importFrom(String path) async {
    var doc = await _read(File(path));
    if (await fileFor(doc.id).exists()) {
      final json = doc.toJson()..['boardId'] = newId();
      doc = BoardDocument.fromJson(json);
    }
    await save(doc);
    return doc;
  }

  // ---- app state (last opened board) ----

  Future<String?> lastOpenedId() async {
    try {
      final json = jsonDecode(await _stateFile.readAsString());
      final id = json is Map ? json['lastOpenedBoard'] : null;
      return id is String ? id : null;
    } on Object {
      return null;
    }
  }

  Future<void> setLastOpened(String? id) async {
    await root.create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({'lastOpenedBoard': id}), flush: true);
    await tmp.rename(_stateFile.path);
  }
}
