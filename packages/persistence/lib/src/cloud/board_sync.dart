import 'dart:convert';

import 'package:local_board_core/local_board_core.dart';

import '../board_store.dart';
import 'remote_store.dart';

/// What one sync did.
final class SyncReport {
  int uploaded = 0;
  int downloaded = 0;
  int trashedHere = 0;
  int deletedThere = 0;

  /// Boards skipped because they were saved by a newer Local Board.
  int needsUpdate = 0;

  bool get changedLocal => downloaded > 0 || trashedHere > 0;

  @override
  String toString() =>
      'uploaded $uploaded, downloaded $downloaded, trashed $trashedHere, deleted remotely $deletedThere'
      '${needsUpdate > 0 ? ', $needsUpdate need a newer app' : ''}';
}

final class _Entry {
  _Entry(this.updatedAt, this.title, {this.deletedAt});

  DateTime updatedAt;
  String title;
  DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Map<String, Object?> toJson() => {
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'title': title,
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  static _Entry? parse(Object? json) {
    if (json is! Map) return null;
    final updated = DateTime.tryParse('${json['updatedAt']}');
    if (updated == null) return null;
    return _Entry(
      updated,
      json['title'] is String ? json['title'] as String : '',
      deletedAt: json['deletedAt'] is String ? DateTime.tryParse(json['deletedAt'] as String) : null,
    );
  }
}

const manifestName = 'manifest.json';

/// Two-way sync between this computer's boards and a storage.
///
/// The storage holds one `.whiteboard` file per board plus a small manifest
/// (id → last change), so a sync only transfers boards that changed. When
/// both sides changed, the newest edit wins and the other version stays in
/// the board's local backup. Boards moved to the trash on one computer are
/// moved to the trash on the others, never destroyed.
///
/// [busy] are boards open in an editor right now: they are uploaded but
/// never replaced underneath the user.
Future<SyncReport> syncBoards(BoardStore store, RemoteStore remote, {Set<String> busy = const {}}) async {
  final report = SyncReport();
  final manifest = <String, _Entry>{};
  final raw = await remote.read(manifestName);
  if (raw != null) {
    try {
      final json = jsonDecode(utf8.decode(raw));
      final boards = json is Map ? json['boards'] : null;
      if (boards is Map) {
        for (final e in boards.entries) {
          final entry = _Entry.parse(e.value);
          if (e.key is String && entry != null) manifest[e.key as String] = entry;
        }
      }
    } on FormatException {
      // A damaged manifest is rebuilt from the boards on this computer.
    }
  }
  var dirty = raw == null;

  Future<void> upload(BoardDocument doc) async {
    await remote.write('${doc.id}${BoardStore.extension}', await store.encode(doc));
    manifest[doc.id] = _Entry(doc.updatedAt, doc.title);
    report.uploaded++;
    dirty = true;
  }

  Future<void> download(String id) async {
    final bytes = await remote.read('$id${BoardStore.extension}');
    if (bytes == null) return;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?>) return;
      await store.save(BoardDocument.fromJson(json));
      report.downloaded++;
    } on UnsupportedSchemaException {
      report.needsUpdate++;
    } on FormatException {
      // Skip a damaged copy; the next upload from its owner replaces it.
    }
  }

  final local = {for (final b in await store.list()) b.id: b};
  for (final summary in local.values) {
    final entry = manifest[summary.id];
    final here = summary.updatedAt;
    if (entry == null) {
      await upload((await store.open(summary.id)).document);
    } else if (entry.deleted) {
      if (here.isAfter(entry.deletedAt!) || busy.contains(summary.id)) {
        await upload((await store.open(summary.id)).document); // edited after it was deleted elsewhere
      } else {
        await store.moveToTrash(summary.id);
        report.trashedHere++;
      }
    } else if (here.isAfter(entry.updatedAt)) {
      await upload((await store.open(summary.id)).document);
    } else if (entry.updatedAt.isAfter(here) && !busy.contains(summary.id)) {
      await download(summary.id);
    }
  }

  final trashed = await store.trashed();
  for (final MapEntry(key: id, value: entry) in manifest.entries.toList()) {
    if (local.containsKey(id) || entry.deleted) continue;
    final deletedAt = trashed[id];
    if (deletedAt != null && !entry.updatedAt.isAfter(deletedAt)) {
      await remote.delete('$id${BoardStore.extension}');
      entry.deletedAt = deletedAt;
      report.deletedThere++;
      dirty = true;
    } else {
      await download(id);
    }
  }

  if (dirty) {
    final json = {
      'format': 'local-board-sync',
      'version': 1,
      'boards': {for (final e in manifest.entries) e.key: e.value.toJson()},
    };
    await remote.write(manifestName, utf8.encode(const JsonEncoder.withIndent(' ').convert(json)));
  }
  return report;
}
