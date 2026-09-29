import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

StrokeObject stroke(String id) =>
    StrokeObject(id: id, points: const [Vec2(0, 0), Vec2(5, 5)], color: 0xFF000000, width: 2);

void main() {
  late Directory tmp;
  late BoardStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lb_test_');
    store = BoardStore(tmp);
  });

  tearDown(() => tmp.delete(recursive: true));

  group('BoardStore', () {
    test('create → save → close → open gives back the same board', () async {
      final doc = await store.create(title: 'Sprint');
      History(doc).execute(AddObjects([stroke('a'), stroke('b')]));
      doc.viewport = const Camera(pan: Vec2(10, 20), zoom: 2);
      await store.save(doc);

      final loaded = await BoardStore(tmp).open(doc.id);
      expect(loaded.wasRecovered, isFalse);
      expect(loaded.document.title, 'Sprint');
      expect(loaded.document.order, ['a', 'b']);
      expect(loaded.document.viewport, doc.viewport);
    });

    test('list is sorted by last edit and survives junk files', () async {
      final a = await store.create(title: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await store.create(title: 'B');
      await File(p.join(store.boardsDir.path, 'garbage.whiteboard')).writeAsString('{not json');
      await File(p.join(store.boardsDir.path, 'notes.txt')).writeAsString('hi');

      final list = await store.list();
      expect(list.map((s) => s.id), [b.id, a.id]);
    });

    test('damaged main file falls back to backup', () async {
      final doc = await store.create(title: 'v1');
      doc.rename('v2');
      await store.save(doc); // v1 is now the .bak
      await store.fileFor(doc.id).writeAsString('{"format":"local-board", truncated');

      final loaded = await store.open(doc.id);
      expect(loaded.wasRecovered, isTrue);
      expect(loaded.recoveredFrom, 'backup');
      expect(loaded.document.title, 'v1');
    });

    test('crash after tmp write but before rename recovers the newer tmp', () async {
      final doc = await store.create(title: 'old');
      doc.rename('newer');
      final tmpFile = File('${store.fileFor(doc.id).path}.tmp');
      await tmpFile.writeAsString(jsonEncode(doc.toJson()));

      final loaded = await store.open(doc.id);
      expect(loaded.document.title, 'newer');
      expect(loaded.recoveredFrom, 'temporary save');
    });

    test('half-written tmp is ignored', () async {
      final doc = await store.create(title: 'good');
      await File('${store.fileFor(doc.id).path}.tmp').writeAsString('{"format":"local-bo');
      final loaded = await store.open(doc.id);
      expect(loaded.document.title, 'good');
      expect(loaded.wasRecovered, isFalse);
    });

    test('missing board throws BoardNotFoundException', () {
      expect(store.open('nope'), throwsA(isA<BoardNotFoundException>()));
    });

    test('board from a newer app is refused, not overwritten', () async {
      final doc = await store.create();
      final json = doc.toJson()..['schemaVersion'] = currentSchemaVersion + 1;
      await store.fileFor(doc.id).writeAsString(jsonEncode(json));
      expect(File('${store.fileFor(doc.id).path}.bak').existsSync(), isFalse);
      expect(store.open(doc.id), throwsA(isA<UnsupportedSchemaException>()));
    });

    test('trash moves every copy, deletes nothing', () async {
      final doc = await store.create();
      await store.save(doc); // creates .bak
      await store.moveToTrash(doc.id);
      expect(await store.list(), isEmpty);
      final trashed = await store.trashDir.list().toList();
      expect(trashed.length, 2);
    });

    test('duplicate gets a new id and keeps content', () async {
      final doc = await store.create(title: 'Original');
      History(doc).execute(AddObjects([stroke('a')]));
      await store.save(doc);
      final copy = await store.duplicate(doc.id);
      expect(copy.id, isNot(doc.id));
      expect(copy.title, 'Original (copy)');
      expect(copy.order, ['a']);
      expect((await store.list()).length, 2);
    });

    test('export then import round-trips; import never overwrites', () async {
      final doc = await store.create(title: 'Portable');
      final out = p.join(tmp.path, 'shared');
      await store.exportTo(doc, out);
      expect(File('$out.whiteboard').existsSync(), isTrue);

      final imported = await store.importFrom('$out.whiteboard');
      expect(imported.id, isNot(doc.id)); // same id existed → fresh id
      expect(imported.title, 'Portable');

      final other = BoardStore(Directory(p.join(tmp.path, 'other')));
      final sameId = await other.importFrom('$out.whiteboard');
      expect(sameId.id, doc.id);
    });

    test('last opened board is remembered', () async {
      expect(await store.lastOpenedId(), isNull);
      await store.setLastOpened('abc');
      expect(await BoardStore(tmp).lastOpenedId(), 'abc');
    });
  });

  group('Autosaver', () {
    test('debounces bursts into one save', () async {
      final doc = BoardDocument.create();
      final history = History(doc);
      var saves = 0;
      final saver = Autosaver(
        document: doc,
        save: (_) async => saves++,
        debounce: const Duration(milliseconds: 30),
      );
      for (var i = 0; i < 10; i++) {
        history.execute(AddObjects([stroke('s$i')]));
        saver.markDirty();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(saves, 1);
      expect(saver.isDirty, isFalse);
      expect(saver.status, SaveStatus.saved);
    });

    test('flush saves immediately', () async {
      final doc = BoardDocument.create();
      var saves = 0;
      final saver = Autosaver(document: doc, save: (_) async => saves++, debounce: const Duration(seconds: 10));
      History(doc).execute(AddObjects([stroke('a')]));
      saver.markDirty();
      await saver.flush();
      expect(saves, 1);
      expect(saver.isDirty, isFalse);
    });

    test('maxDelay forces a save during continuous editing', () async {
      final doc = BoardDocument.create();
      final history = History(doc);
      var saves = 0;
      final saver = Autosaver(
        document: doc,
        save: (_) async => saves++,
        debounce: const Duration(milliseconds: 40),
        maxDelay: const Duration(milliseconds: 100),
      );
      for (var i = 0; i < 15; i++) {
        history.execute(AddObjects([stroke('s$i')]));
        saver.markDirty();
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(saves, greaterThanOrEqualTo(1));
      await saver.dispose();
    });

    test('edits during a save trigger a follow-up save', () async {
      final doc = BoardDocument.create();
      final history = History(doc);
      final gate = Completer<void>();
      var saves = 0;
      final saver = Autosaver(
        document: doc,
        save: (_) async {
          saves++;
          if (saves == 1) await gate.future;
        },
        debounce: const Duration(milliseconds: 5),
      );
      history.execute(AddObjects([stroke('a')]));
      saver.markDirty();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      history.execute(AddObjects([stroke('b')])); // while save #1 is blocked
      saver.markDirty();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(saves, 2);
      expect(saver.isDirty, isFalse);
    });

    test('camera moves are saved but do not count as edits', () async {
      final doc = BoardDocument.create();
      final before = doc.updatedAt;
      var saves = 0;
      final saver = Autosaver(document: doc, save: (_) async => saves++, debounce: const Duration(milliseconds: 5));
      doc.setViewport(const Camera(pan: Vec2(5, 5), zoom: 2));
      saver.markDirty();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(saves, 1);
      expect(doc.updatedAt, before);
      expect(doc.revision, 0);
    });

    test('failed save reports error and keeps data dirty', () async {
      final doc = BoardDocument.create();
      final statuses = <SaveStatus>[];
      final saver = Autosaver(
        document: doc,
        save: (_) async => throw const FileSystemException('disk full'),
        debounce: const Duration(milliseconds: 5),
        onStatus: (s, _) => statuses.add(s),
      );
      History(doc).execute(AddObjects([stroke('a')]));
      saver.markDirty();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(saver.status, SaveStatus.error);
      expect(saver.isDirty, isTrue);
      expect(statuses, contains(SaveStatus.error));
    });
  });

  test('data dir honours override and XDG', () {
    expect(defaultDataDirectory(environment: {'LOCAL_BOARD_DATA_DIR': '/x'}).path, '/x');
    if (Platform.isLinux) {
      expect(defaultDataDirectory(environment: {'HOME': '/h', 'XDG_DATA_HOME': '/d'}).path, '/d/local-board');
      expect(defaultDataDirectory(environment: {'HOME': '/h'}).path, '/h/.local/share/local-board');
    }
  });
}
