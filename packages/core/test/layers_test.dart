import 'dart:convert';
import 'dart:typed_data';

import 'package:local_board_core/local_board_core.dart';
import 'package:test/test.dart';

/// A 1x1 PNG, enough for the signature check and hashing.
final pngBytes = Uint8List.fromList(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
);

StrokeObject stroke(String id) =>
    StrokeObject(id: id, points: const [Vec2(0, 0), Vec2(10, 10)], color: 0xFF000000, width: 2);

ImageObject image(String id, BoardAsset asset, {Vec2 at = Vec2.zero, Vec2 size = const Vec2(200, 100)}) => ImageObject(
  id: id,
  assetId: asset.id,
  mime: asset.mime,
  position: at,
  size: size,
  naturalSize: const Vec2(400, 200),
);

BoardDocument newDoc([List<BoardObject> objects = const []]) =>
    BoardDocument(id: 'b', title: 'B', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026), objects: objects);

void main() {
  final asset = BoardAsset.fromBytes(pngBytes);

  group('assets', () {
    test('ids are content hashes and the type is sniffed from the bytes', () {
      expect(asset.mime, 'image/png');
      expect(asset.id, hasLength(32));
      expect(BoardAsset.fromBytes(pngBytes).id, asset.id);
      expect(asset.fileName, '${asset.id}.png');
    });

    test('non pictures are refused', () {
      expect(BoardAsset.sniffImageMime(utf8.encode('hello world')), isNull);
      expect(() => BoardAsset.fromBytes(Uint8List.fromList(utf8.encode('nope'))), throwsFormatException);
    });

    test('sniffs the usual formats', () {
      expect(BoardAsset.sniffImageMime([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(BoardAsset.sniffImageMime(utf8.encode('GIF89a')), 'image/gif');
      expect(BoardAsset.sniffImageMime([...utf8.encode('RIFF'), 0, 0, 0, 0, ...utf8.encode('WEBP')]), 'image/webp');
      expect(BoardAsset.sniffImageMime([0x42, 0x4D, 0, 0]), 'image/bmp');
    });

    test('fitImageSize shrinks to the view and caps huge pictures', () {
      expect(fitImageSize(const Vec2(100, 50), const Vec2(1000, 800)), const Vec2(100, 50)); // small stays natural
      final big = fitImageSize(const Vec2(4000, 2000), const Vec2(1000, 800));
      expect(big.x, closeTo(700, 0.001)); // 70% of the view width
      expect(big.y / big.x, closeTo(0.5, 1e-9)); // proportions kept
      final huge = fitImageSize(const Vec2(20000, 10000), const Vec2(0, 0));
      expect(huge.x, 4000);
    });
  });

  group('ImageObject', () {
    test('json round trip, bounds, translate', () {
      final i = image('i', asset, at: const Vec2(10, 20));
      final back = ImageObject.fromJson(jsonDecode(jsonEncode(i.toJson())) as Map<String, Object?>);
      expect(back.assetId, asset.id);
      expect(back.bounds, const Bounds(10, 20, 210, 120));
      expect(i.translate(const Vec2(5, 5)).position, const Vec2(15, 25));
      expect(i.withId('z').id, 'z');
    });

    test('resize keeps the proportions', () {
      final i = image('i', asset); // 200 x 100
      const from = Bounds(0, 0, 200, 100);
      final r = i.resize(from, const Bounds(0, 0, 400, 150));
      expect(r.size.x / r.size.y, closeTo(2, 1e-9));
      expect(r.size.x, 400);
      final small = i.resize(from, const Bounds(0, 0, 1, 1));
      expect(small.size.y, greaterThanOrEqualTo(ImageObject.minSide));
      expect(small.size.x / small.size.y, closeTo(2, 1e-9));
    });

    test('a hostile asset id is rejected so it never becomes a path', () {
      final json = image('i', asset).toJson()..['assetId'] = '../../evil';
      expect(() => ImageObject.fromJson(json), throwsFormatException);
    });
  });

  group('layer order', () {
    test('forward and backward step past one neighbour', () {
      final history = History(newDoc([stroke('a'), stroke('b'), stroke('c'), stroke('d')]));
      history.execute(ReorderObjects(['a'], ZMove.forward));
      expect(history.document.order, ['b', 'a', 'c', 'd']);
      history.execute(ReorderObjects(['d'], ZMove.backward));
      expect(history.document.order, ['b', 'a', 'd', 'c']);
      history.undo();
      history.undo();
      expect(history.document.order, ['a', 'b', 'c', 'd']);
    });

    test('a selected block moves together and keeps its internal order', () {
      expect(reorderedIds(['a', 'b', 'c', 'd', 'e'], {'b', 'c'}, ZMove.forward), ['a', 'd', 'b', 'c', 'e']);
      expect(reorderedIds(['a', 'b', 'c', 'd', 'e'], {'b', 'd'}, ZMove.backward), ['b', 'a', 'd', 'c', 'e']);
      expect(reorderedIds(['a', 'b', 'c'], {'c'}, ZMove.forward), ['a', 'b', 'c']); // already on top
      expect(reorderedIds(['a', 'b', 'c'], {'a', 'c'}, ZMove.toFront), ['b', 'a', 'c']);
    });

    test('SetOrder is undoable and refuses non permutations', () {
      final doc = newDoc([stroke('a'), stroke('b'), stroke('c')]);
      final history = History(doc);
      history.execute(SetOrder(['c', 'a', 'b']));
      expect(doc.order, ['c', 'a', 'b']);
      history.undo();
      expect(doc.order, ['a', 'b', 'c']);
      expect(() => SetOrder(['a']).apply(doc), throwsStateError);
    });

    test('drawing goes above or below an image depending on its layer', () {
      final doc = newDoc([image('img', asset)])..addAsset(asset);
      final history = History(doc);
      history.execute(AddObjects([stroke('pen')]));
      expect(doc.layersTopDown.map((o) => o.id), ['pen', 'img']); // over the picture
      history.execute(ReorderObjects(['pen'], ZMove.toBack));
      expect(doc.layersTopDown.map((o) => o.id), ['img', 'pen']); // under it
    });
  });

  group('layer props', () {
    test('hidden objects are not picked, not in bounds, not exported', () {
      final doc = newDoc([image('img', asset), stroke('s')])..addAsset(asset);
      final history = History(doc);
      expect(doc.hitTest(const Vec2(5, 5), 1)!.id, 's'); // stroke is on top
      history.execute(SetLayerProps({'s': const LayerProps(visible: false)}, label: 'Hide'));
      expect(doc.hitTest(const Vec2(5, 5), 1)!.id, 'img');
      expect(doc.contentBounds, doc['img']!.bounds);
      expect(exportSvg(doc), isNot(contains('<path')));
      expect(exportSvg(doc), contains('<image'));
      history.undo();
      expect(doc.isVisible('s'), isTrue);
      expect(exportSvg(doc), contains('<path'));
    });

    test('locked objects cannot be picked or marquee-selected, so you can draw over them', () {
      final doc = newDoc([image('img', asset)]);
      History(doc).execute(SetLayerProps({'img': const LayerProps(locked: true)}, label: 'Lock'));
      expect(doc.hitTest(const Vec2(50, 50), 1), isNull);
      expect(doc.objectsInside(const Bounds(-10, -10, 500, 500)), isEmpty);
      expect(doc.isEditable('img'), isFalse);
      expect(doc.contentBounds, isNotNull); // still visible
    });

    test('names: custom, default, and reset', () {
      final doc = newDoc([image('img', asset), stroke('s')]);
      expect(doc.layerName('img'), 'Image');
      expect(doc.layerName('s'), 'Drawing');
      final history = History(doc);
      history.execute(SetLayerProps({'img': const LayerProps(name: 'Floor plan')}, label: 'Rename'));
      expect(doc.layerName('img'), 'Floor plan');
      history.undo();
      expect(doc.layerName('img'), 'Image');
    });

    test('delete then undo restores position, name, lock and visibility', () {
      final doc = newDoc([stroke('a'), stroke('b'), stroke('c')]);
      final history = History(doc);
      history.execute(SetLayerProps({'b': const LayerProps(name: 'mid', locked: true, visible: false)}, label: 'x'));
      history.execute(DeleteObjects(['b']));
      expect(doc.contains('b'), isFalse);
      expect(doc.propsOf('b').isDefault, isTrue);
      history.undo();
      expect(doc.order, ['a', 'b', 'c']);
      expect(doc.propsOf('b'), const LayerProps(name: 'mid', locked: true, visible: false));
    });

    test('props survive serialization; defaults add nothing to the file', () {
      final doc = newDoc([stroke('a'), stroke('b')]);
      doc.setProps('a', const LayerProps(name: 'ink', locked: true, visible: false));
      final json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>;
      final objects = (json['objects']! as List).cast<Map<String, Object?>>();
      expect(objects[0]['name'], 'ink');
      expect(objects[0]['hidden'], true);
      expect(objects[0]['locked'], true);
      expect(objects[1].containsKey('name'), isFalse);
      expect(objects[1].containsKey('hidden'), isFalse);
      final back = BoardDocument.fromJson(json);
      expect(back.propsOf('a'), const LayerProps(name: 'ink', locked: true, visible: false));
      expect(back.propsOf('b').isDefault, isTrue);
    });
  });

  group('documents with pictures', () {
    test('picture bytes stay out of the JSON unless embedding', () {
      final doc = newDoc([image('img', asset)])..addAsset(asset);
      expect(jsonEncode(doc.toJson()), isNot(contains('"data"')));
      expect(doc.toJson().containsKey('assets'), isFalse);
      final embedded = jsonDecode(jsonEncode(doc.toJson(embedAssets: true))) as Map<String, Object?>;
      final back = BoardDocument.fromJson(embedded);
      expect(back.asset(asset.id)!.bytes, pngBytes);
      expect(back.referencedAssetIds, {asset.id});
    });

    test('add, move and undo an image through commands', () {
      final doc = newDoc()..addAsset(asset);
      final history = History(doc);
      final img = image('img', asset);
      history.execute(AddObjects([img]));
      history.execute(UpdateObjects.move([img], const Vec2(30, 40)));
      expect((doc['img']! as ImageObject).position, const Vec2(30, 40));
      history.undo();
      history.undo();
      expect(doc.isEmpty, isTrue);
      history.redo();
      expect(doc.contains('img'), isTrue);
    });

    test('SVG embeds the picture as a data URI, or a placeholder if bytes are gone', () {
      final doc = newDoc([image('img', asset)]);
      expect(exportSvg(doc), isNot(contains('<image')));
      expect(exportSvg(doc), contains('fill="#ece9ff"'));
      doc.addAsset(asset);
      final svg = exportSvg(doc);
      expect(svg, contains('<image'));
      expect(svg, contains('data:image/png;base64,${base64Encode(pngBytes)}'));
    });

    test('schema 2 boards migrate unchanged', () {
      final json = newDoc([stroke('a')]).toJson()..['schemaVersion'] = 2;
      final doc = BoardDocument.fromJson(json);
      expect(doc.length, 1);
      expect(doc.toJson()['schemaVersion'], 3);
    });
  });
}
