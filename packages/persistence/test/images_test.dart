import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final pngBytes = Uint8List.fromList(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
);

/// Remote kept in memory.
final class MemoryRemote implements RemoteStore {
  final files = <String, List<int>>{};
  int writes = 0;

  @override
  Future<List<int>?> read(String name) async => files[name];

  @override
  Future<void> write(String name, List<int> bytes) async {
    writes++;
    files[name] = bytes;
  }

  @override
  Future<void> delete(String name) async => files.remove(name);
}

ImageObject imageOf(String id, BoardAsset a) => ImageObject(
  id: id,
  assetId: a.id,
  mime: a.mime,
  position: Vec2.zero,
  size: const Vec2(100, 50),
  naturalSize: const Vec2(1, 1),
);

void main() {
  late Directory tmp;
  late BoardStore store;
  late BoardAsset asset;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lb_img_');
    store = BoardStore(Directory(p.join(tmp.path, 'a')));
    asset = BoardAsset.fromBytes(pngBytes);
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<BoardDocument> boardWithImage(BoardStore s) async {
    final doc = await s.create(title: 'Pics');
    doc.addAsset(asset);
    History(doc).execute(
      CompositeCommand([
        AddObjects([imageOf('img', asset)]),
        SetLayerProps({'img': const LayerProps(name: 'Photo', locked: true)}, label: 'x'),
      ], label: 'Add image'),
    );
    await s.save(doc);
    return doc;
  }

  group('pictures on disk', () {
    test('bytes go to assets/, not into the board file, and come back on open', () async {
      final doc = await boardWithImage(store);

      expect(File(p.join(store.assetsDir.path, asset.fileName)).readAsBytesSync(), pngBytes);
      final json = File(store.fileFor(doc.id).path).readAsStringSync();
      expect(json, isNot(contains('iVBOR'))); // no base64 in the JSON
      expect(json, contains(asset.id));

      final loaded = (await BoardStore(store.root).open(doc.id)).document;
      expect(loaded.asset(asset.id)!.bytes, pngBytes);
      expect(loaded.propsOf('img'), const LayerProps(name: 'Photo', locked: true));
      expect(loaded['img'], isA<ImageObject>());
    });

    test('the same picture in two boards is stored once', () async {
      await boardWithImage(store);
      await boardWithImage(store);
      expect(store.assetsDir.listSync().whereType<File>().where((f) => !f.path.endsWith('.tmp')), hasLength(1));
    });

    test('a missing asset file does not stop the board from opening', () async {
      final doc = await boardWithImage(store);
      File(p.join(store.assetsDir.path, asset.fileName)).deleteSync();
      final loaded = (await BoardStore(store.root).open(doc.id)).document;
      expect(loaded.contains('img'), isTrue);
      expect(loaded.asset(asset.id), isNull);
    });

    test('the board list does not read picture bytes', () async {
      await boardWithImage(store);
      final list = await store.list();
      expect(list.single.objectCount, 1);
    });

    test('duplicate keeps the pictures', () async {
      final doc = await boardWithImage(store);
      final copy = await store.duplicate(doc.id);
      final reopened = (await store.open(copy.id)).document;
      expect(reopened.asset(asset.id)!.bytes, pngBytes);
      expect(reopened.propsOf('img').name, 'Photo');
    });

    test('exported copies carry their pictures and import on another computer', () async {
      final doc = await boardWithImage(store);
      final file = p.join(tmp.path, 'share.whiteboard');
      await store.exportTo(doc, file);
      expect(File(file).readAsStringSync(), contains('"assets"'));

      final other = BoardStore(Directory(p.join(tmp.path, 'b')));
      final imported = await other.importFrom(file);
      expect(imported.asset(asset.id)!.bytes, pngBytes);
      final reopened = (await other.open(imported.id)).document;
      expect(reopened.asset(asset.id)!.bytes, pngBytes);
      expect(File(p.join(other.assetsDir.path, asset.fileName)).existsSync(), isTrue);
    });
  });

  group('sync with pictures', () {
    test('pictures travel with the board, once, and the other computer can show them', () async {
      final remote = MemoryRemote();
      final doc = await boardWithImage(store);
      final other = BoardStore(Directory(p.join(tmp.path, 'b')));

      expect((await syncBoards(store, remote)).uploaded, 1);
      expect(remote.files.containsKey('$assetPrefix${asset.fileName}'), isTrue);
      expect(remote.files['$assetPrefix${asset.fileName}'], pngBytes);
      final manifest = jsonDecode(utf8.decode(remote.files[manifestName]!)) as Map<String, Object?>;
      expect(manifest['assets'], [asset.fileName]);

      expect((await syncBoards(other, remote)).downloaded, 1);
      final there = (await other.open(doc.id)).document;
      expect(there.asset(asset.id)!.bytes, pngBytes);

      // A second edit does not re-upload the picture.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final writesBefore = remote.writes;
      final edited = (await store.open(doc.id)).document;
      History(edited).execute(
        AddObjects([StrokeObject(id: 's', points: const [Vec2(0, 0), Vec2(1, 1)], color: 0xFF000000, width: 2)]),
      );
      await store.save(edited);
      await syncBoards(store, remote);
      expect(remote.writes - writesBefore, 2); // the board and the manifest, not the picture
    });

    test('old manifests without an asset list still work', () async {
      final remote = MemoryRemote();
      await store.create(title: 'Plain');
      await syncBoards(store, remote);
      final manifest = jsonDecode(utf8.decode(remote.files[manifestName]!)) as Map<String, Object?>..remove('assets');
      remote.files[manifestName] = utf8.encode(jsonEncode(manifest));
      final report = await syncBoards(store, remote);
      expect(report.uploaded + report.downloaded, 0);
    });
  });
}
