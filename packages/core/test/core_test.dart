import 'dart:convert';

import 'package:local_board_core/local_board_core.dart';
import 'package:test/test.dart';

const ink = 0xFF17181A;

StrokeObject stroke(String id, [double x = 0]) =>
    StrokeObject(id: id, points: [Vec2(x, 0), Vec2(x + 10, 10)], color: ink, width: 2);

ShapeObject rect(String id, {int? fill}) => ShapeObject(
  id: id,
  kind: ShapeKind.rectangle,
  start: const Vec2(0, 0),
  end: const Vec2(100, 50),
  strokeColor: ink,
  strokeWidth: 2,
  fillColor: fill,
);

void main() {
  group('geometry', () {
    test('distanceToSegment clamps to endpoints', () {
      expect(distanceToSegment(const Vec2(5, 5), Vec2.zero, const Vec2(10, 0)), 5);
      expect(distanceToSegment(const Vec2(-3, 4), Vec2.zero, const Vec2(10, 0)), 5);
    });

    test('Bounds.enclosing and union', () {
      final b = Bounds.enclosing(const [Vec2(3, -1), Vec2(-2, 4), Vec2(1, 1)]);
      expect(b, const Bounds(-2, -1, 3, 4));
      expect(Bounds.union([b, const Bounds(10, 10, 11, 11)]), const Bounds(-2, -1, 11, 11));
      expect(Bounds.union([]), isNull);
    });

    test('snapAngle45 snaps to diagonals and axes', () {
      final p = snapAngle45(Vec2.zero, const Vec2(10, 9));
      expect(p.x, closeTo(p.y, 1e-9));
      final h = snapAngle45(Vec2.zero, const Vec2(10, 1));
      expect(h.y, closeTo(0, 1e-9));
    });

    test('snapSquare keeps drag direction', () {
      expect(snapSquare(Vec2.zero, const Vec2(-10, 4)), const Vec2(-10, 10));
    });
  });

  group('viewport', () {
    test('toWorld/toScreen round-trip', () {
      const v = Camera(pan: Vec2(40, -20), zoom: 2);
      final w = v.toWorld(const Vec2(100, 100));
      expect(v.toScreen(w), const Vec2(100, 100));
    });

    test('zoomAt keeps the focal point fixed', () {
      const v = Camera(pan: Vec2(13, 7), zoom: 1.5);
      const focal = Vec2(300, 200);
      final before = v.toWorld(focal);
      final z = v.zoomAt(focal, 1.7);
      expect(z.toWorld(focal).x, closeTo(before.x, 1e-9));
      expect(z.toWorld(focal).y, closeTo(before.y, 1e-9));
    });

    test('zoom is clamped', () {
      expect(const Camera().zoomAt(Vec2.zero, 1000).zoom, Camera.maxZoom);
      expect(const Camera().zoomAt(Vec2.zero, 0.0001).zoom, Camera.minZoom);
    });

    test('fit centers content', () {
      final v = Camera.fit(const Bounds(0, 0, 100, 100), const Vec2(800, 600));
      expect(v.toScreen(const Vec2(50, 50)), const Vec2(400, 300));
    });
  });

  group('hit testing', () {
    test('stroke is hit near its segments only', () {
      final s = stroke('s');
      expect(s.hitTest(const Vec2(5, 5), 1), isTrue);
      expect(s.hitTest(const Vec2(10, 0), 1), isFalse);
    });

    test('unfilled rectangle is hit on its outline, filled one inside', () {
      expect(rect('r').hitTest(const Vec2(50, 25), 2), isFalse);
      expect(rect('r').hitTest(const Vec2(0, 25), 2), isTrue);
      expect(rect('r', fill: 0xFFFFFFFF).hitTest(const Vec2(50, 25), 2), isTrue);
    });

    test('ellipse outline', () {
      const e = ShapeObject(
        id: 'e',
        kind: ShapeKind.ellipse,
        start: Vec2(0, 0),
        end: Vec2(100, 100),
        strokeColor: ink,
        strokeWidth: 2,
      );
      expect(e.hitTest(const Vec2(100, 50), 2), isTrue);
      expect(e.hitTest(const Vec2(50, 50), 2), isFalse);
    });

    test('document returns topmost object', () {
      final doc = BoardDocument.create()
        ..insertAt(0, rect('bottom', fill: 0xFFFFFFFF))
        ..insertAt(1, rect('top', fill: 0xFF000000));
      expect(doc.hitTest(const Vec2(10, 10), 1)!.id, 'top');
    });
  });

  group('commands and history', () {
    late BoardDocument doc;
    late History history;

    setUp(() {
      doc = BoardDocument.create();
      history = History(doc);
    });

    test('add / undo / redo', () {
      history.execute(AddObjects([stroke('a'), stroke('b')]));
      expect(doc.order, ['a', 'b']);
      expect(history.undo(), isTrue);
      expect(doc.isEmpty, isTrue);
      expect(history.redo(), isTrue);
      expect(doc.order, ['a', 'b']);
    });

    test('delete restores z-order on undo', () {
      history.execute(AddObjects([stroke('a'), stroke('b'), stroke('c'), stroke('d')]));
      history.execute(DeleteObjects(['d', 'b']));
      expect(doc.order, ['a', 'c']);
      history.undo();
      expect(doc.order, ['a', 'b', 'c', 'd']);
    });

    test('move is reversible and keeps identity', () {
      history.execute(AddObjects([rect('r')]));
      history.execute(UpdateObjects.move([doc['r']!], const Vec2(10, 5)));
      expect((doc['r']! as ShapeObject).start, const Vec2(10, 5));
      history.undo();
      expect((doc['r']! as ShapeObject).start, Vec2.zero);
    });

    test('reorder', () {
      history.execute(AddObjects([stroke('a'), stroke('b'), stroke('c')]));
      history.execute(ReorderObjects(['a'], ZMove.toFront));
      expect(doc.order, ['b', 'c', 'a']);
      history.execute(ReorderObjects(['c'], ZMove.toBack));
      expect(doc.order, ['c', 'b', 'a']);
      history.undo();
      history.undo();
      expect(doc.order, ['a', 'b', 'c']);
    });

    test('new command clears redo', () {
      history.execute(AddObjects([stroke('a')]));
      history.undo();
      history.execute(AddObjects([stroke('b')]));
      expect(history.canRedo, isFalse);
    });

    test('composite undoes as one step', () {
      history.execute(AddObjects([stroke('a')]));
      history.execute(
        CompositeCommand([DeleteObjects(['a']), AddObjects([stroke('b')]), RenameBoard('X')], label: 'Replace'),
      );
      expect(doc.order, ['b']);
      expect(doc.title, 'X');
      history.undo();
      expect(doc.order, ['a']);
      expect(doc.title, 'Untitled board');
    });

    test('history limit drops oldest', () {
      final h = History(doc, limit: 3);
      for (var i = 0; i < 5; i++) {
        h.execute(AddObjects([stroke('s$i')]));
      }
      var undone = 0;
      while (h.undo()) {
        undone++;
      }
      expect(undone, 3);
      expect(doc.order, ['s0', 's1']);
    });

    test('revision bumps on every change', () {
      final r0 = doc.revision;
      history.execute(AddObjects([stroke('a')]));
      history.undo();
      expect(doc.revision, r0 + 2);
    });
  });

  group('serialization', () {
    test('round-trips every object type through JSON text', () {
      final doc = BoardDocument.create(title: 'Plan')
        ..viewport = const Camera(pan: Vec2(12.5, -3), zoom: 1.25)
        ..insertAt(0, stroke('s'))
        ..insertAt(1, rect('r', fill: 0x80FFCC00))
        ..insertAt(
          2,
          const ShapeObject(
            id: 'a',
            kind: ShapeKind.arrow,
            start: Vec2(1, 2),
            end: Vec2(3, 4),
            strokeColor: ink,
            strokeWidth: 3,
          ),
        )
        ..insertAt(
          3,
          const TextObject(id: 't', position: Vec2(5, 6), text: 'Hola\nmundo', fontSize: 24, color: ink, size: Vec2(80, 60)),
        )
        ..insertAt(4, const StickyNote(id: 'n', position: Vec2(7, 8), size: Vec2(200, 200), text: 'Idea', color: 0xFFFFE08A));

      final text = jsonEncode(doc.toJson());
      final back = BoardDocument.fromJson(jsonDecode(text) as Map<String, Object?>);

      expect(back.id, doc.id);
      expect(back.title, 'Plan');
      expect(back.viewport, doc.viewport);
      expect(back.order, doc.order);
      expect(jsonEncode(back.toJson()), text);
      expect((back['r']! as ShapeObject).fillColor, 0x80FFCC00);
      expect((back['t']! as TextObject).text, 'Hola\nmundo');
    });

    test('colors use #rrggbbaa', () {
      expect(colorToJson(0x80FFCC00), '#ffcc0080');
      expect(colorFromJson('#ffcc0080'), 0x80FFCC00);
      expect(colorFromJson('#ffcc00'), 0xFFFFCC00);
    });

    test('rejects non-board JSON, newer schema and duplicate ids', () {
      expect(() => BoardDocument.fromJson({'hello': 1}), throwsFormatException);
      final json = BoardDocument.create().toJson()..['schemaVersion'] = currentSchemaVersion + 1;
      expect(() => BoardDocument.fromJson(json), throwsA(isA<UnsupportedSchemaException>()));
      final dup = BoardDocument.create().toJson()
        ..['objects'] = [stroke('x').toJson(), stroke('x').toJson()];
      expect(() => BoardDocument.fromJson(dup), throwsFormatException);
    });

    test('unknown object type fails loudly', () {
      final json = BoardDocument.create().toJson()
        ..['objects'] = [
          {'type': 'hologram', 'id': 'h'},
        ];
      expect(() => BoardDocument.fromJson(json), throwsFormatException);
    });
  });

  group('migrations', () {
    test('runs each step in order up to target', () {
      final steps = <int, Migration>{
        1: (j) => j..['a'] = 'v2',
        2: (j) => j..['b'] = 'v3',
      };
      final out = migrateToCurrent({'format': 'local-board', 'schemaVersion': 1}, steps: steps, target: 3);
      expect(out['schemaVersion'], 3);
      expect(out['a'], 'v2');
      expect(out['b'], 'v3');
    });

    test('missing step is an error, not silent data loss', () {
      expect(
        () => migrateToCurrent({'format': 'local-board', 'schemaVersion': 1}, steps: {}, target: 2),
        throwsStateError,
      );
    });
  });

  group('resize and export', () {
    test('resize maps shapes and strokes into the new frame', () {
      const from = Bounds(0, 0, 100, 50);
      const to = Bounds(10, 10, 210, 60);
      final r = rect('r').resize(from, to);
      expect(r.start, const Vec2(10, 10));
      expect(r.end, const Vec2(210, 60));
      final s = stroke('s').resize(const Bounds(0, 0, 10, 10), const Bounds(0, 0, 20, 20));
      expect(s.points.last, const Vec2(20, 20));
    });

    test('text scales uniformly by height', () {
      const t = TextObject(id: 't', position: Vec2(0, 0), text: 'x', fontSize: 20, color: ink, size: Vec2(40, 26));
      final big = t.resize(t.bounds, const Bounds(0, 0, 80, 52));
      expect(big.fontSize, 40);
      expect(big.size, const Vec2(80, 52));
    });

    test('SVG export contains every object and escapes text', () {
      final doc = BoardDocument.create(title: 'A & B')
        ..insertAt(0, stroke('s'))
        ..insertAt(1, rect('r'))
        ..insertAt(
          2,
          const ShapeObject(
            id: 'a',
            kind: ShapeKind.arrow,
            start: Vec2(0, 0),
            end: Vec2(50, 0),
            strokeColor: ink,
            strokeWidth: 2,
          ),
        )
        ..insertAt(
          3,
          const TextObject(id: 't', position: Vec2(0, 80), text: '<hi>\nthere', fontSize: 20, color: ink, size: Vec2(60, 52)),
        )
        ..insertAt(4, const StickyNote(id: 'n', position: Vec2(200, 0), size: Vec2(200, 200), text: 'note', color: 0xFFFFE08A));
      final svg = exportSvg(doc);
      expect(svg, startsWith('<?xml'));
      expect(svg, contains('<title>A &amp; B</title>'));
      expect(svg, contains('<path d="M'));
      expect(svg, contains('<rect'));
      expect(svg, contains('<polyline'));
      expect(svg, contains('&lt;hi&gt;'));
      expect(svg, contains('>note<'));
      expect('<tspan'.allMatches(svg).length, 3);
    });
  });

  test('ids are unique 32-char hex', () {
    final ids = {for (var i = 0; i < 1000; i++) newId()};
    expect(ids.length, 1000);
    expect(ids.every((id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id)), isTrue);
  });

  test('stress: 10,000 objects serialize and hit-test in reasonable time', () {
    final doc = BoardDocument.create();
    for (var i = 0; i < 10000; i++) {
      doc.insertAt(i, stroke('s$i', i * 20.0));
    }
    final sw = Stopwatch()..start();
    final text = jsonEncode(doc.toJson());
    final back = BoardDocument.fromJson(jsonDecode(text) as Map<String, Object?>);
    expect(back.length, 10000);
    expect(back.hitTest(const Vec2(5, 5), 1)!.id, 's0');
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
