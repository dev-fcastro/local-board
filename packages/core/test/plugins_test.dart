import 'dart:convert';

import 'package:local_board_core/local_board_core.dart';
import 'package:test/test.dart';

ComponentObject component(String id, {String plugin = 'software-architecture', String kind = 'database'}) =>
    ComponentObject(
      id: id,
      plugin: plugin,
      kind: kind,
      position: const Vec2(10, 20),
      size: const Vec2(150, 120),
      label: 'Orders DB',
      color: 0xFF4F46E5,
    );

/// Every point an icon part draws through, to check it stays on the grid.
Iterable<(double, double)> _points(IconPart part) sync* {
  switch (part) {
    case IconLine l:
      yield (l.x1, l.y1);
      yield (l.x2, l.y2);
    case IconRect r:
      yield (r.x, r.y);
      yield (r.x + r.width, r.y + r.height);
    case IconCircle c:
      yield (c.cx - c.r, c.cy - c.r);
      yield (c.cx + c.r, c.cy + c.r);
    case IconEllipse e:
      yield (e.cx - e.rx, e.cy - e.ry);
      yield (e.cx + e.rx, e.cy + e.ry);
    case IconPolyline p:
      for (var i = 0; i + 1 < p.points.length; i += 2) {
        yield (p.points[i], p.points[i + 1]);
      }
    case IconPath p:
      for (final s in parseIconPath(p.data)) {
        switch (s) {
          case MoveTo(:final x, :final y) || LineTo(:final x, :final y):
            yield (x, y);
          case CubicTo c:
            yield (c.x, c.y);
          case ClosePath():
        }
      }
  }
}

void main() {
  group('plugin registry', () {
    test('built-in plugins have unique ids and valid kinds', () {
      final ids = builtInPlugins.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['software-architecture', 'network-architecture']));
      for (final plugin in builtInPlugins) {
        final kinds = plugin.kinds.map((k) => k.id).toList();
        expect(kinds.toSet().length, kinds.length, reason: plugin.id);
        expect(plugin.kinds.where((k) => k.body == ComponentBody.zone), hasLength(1), reason: plugin.id);
        for (final kind in plugin.kinds) {
          expect(kind.icon.parts, isNotEmpty, reason: kind.id);
          expect(findComponentKind(plugin.id, kind.id), same(kind));
          for (final part in kind.icon.parts) {
            for (final (x, y) in _points(part)) {
              expect(x, inInclusiveRange(0, ComponentIcon.grid), reason: '${plugin.id}/${kind.id} x=$x');
              expect(y, inInclusiveRange(0, ComponentIcon.grid), reason: '${plugin.id}/${kind.id} y=$y');
            }
          }
        }
      }
    });

    test('unknown plugins resolve to nothing', () {
      expect(findPlugin('nope'), isNull);
      expect(findComponentKind('software-architecture', 'nope'), isNull);
    });
  });

  group('icon paths', () {
    test('parses M L H V C Z', () {
      final s = parseIconPath('M1 2 L3 4 H5 V6 C1 2 3 4 5 6 Z');
      expect(s, hasLength(6));
      expect(s[0], isA<MoveTo>());
      final h = s[2] as LineTo;
      expect((h.x, h.y), (5.0, 4.0));
      final v = s[3] as LineTo;
      expect((v.x, v.y), (5.0, 6.0));
      expect(s[4], isA<CubicTo>());
      expect(s[5], isA<ClosePath>());
    });

    test('extra pairs after M are lines', () {
      final s = parseIconPath('M0 0 10 10');
      expect(s[1], isA<LineTo>());
    });

    test('rejects malformed paths', () {
      expect(() => parseIconPath('0 0 L1 1'), throwsFormatException);
      expect(() => parseIconPath('M1'), throwsFormatException);
    });
  });

  group('components', () {
    test('round-trip through JSON', () {
      final c = component('c1');
      final back = BoardObject.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(back, isA<ComponentObject>());
      expect(back.toJson(), c.toJson());
    });

    test('a component from an unknown plugin still loads and draws a placeholder', () {
      final c = component('c1', plugin: 'from-the-future', kind: 'widget');
      final back = BoardObject.fromJson(c.toJson()) as ComponentObject;
      expect(back.definition, isNull);
      expect(back.icon, same(unknownComponentIcon));
      expect(back.isZone, isFalse);
    });

    test('rejects components without plugin or kind', () {
      final json = component('c1').toJson()..remove('kind');
      expect(() => BoardObject.fromJson(json), throwsFormatException);
    });

    test('cards are solid, zones only react on their edges and header', () {
      final card = component('c1');
      expect(card.hitTest(const Vec2(80, 80), 2), isTrue);
      final zone = ComponentObject(
        id: 'z',
        plugin: 'network-architecture',
        kind: 'network-zone',
        position: Vec2.zero,
        size: const Vec2(400, 300),
        label: 'DMZ',
        color: 0xFF0891B2,
      );
      expect(zone.isZone, isTrue);
      expect(zone.hitTest(const Vec2(200, 150), 2), isFalse);
      expect(zone.hitTest(const Vec2(200, 10), 2), isTrue);
      expect(zone.hitTest(const Vec2(1, 150), 2), isTrue);
      expect(zone.hitTest(const Vec2(200, 299), 2), isTrue);
    });

    test('resize keeps a minimum size', () {
      final c = component('c1');
      final r = c.resize(c.bounds, Bounds(c.bounds.left, c.bounds.top, c.bounds.left + 5, c.bounds.top + 5));
      expect(r.size, const Vec2(40, 40));
    });

    test('card layout puts the icon above the label', () {
      final l = ComponentLayout.of(component('c1'));
      expect(l.icon.width, l.icon.height);
      expect(l.icon.bottom, lessThanOrEqualTo(l.label.top));
      expect(l.icon.width, ComponentStyle.maxIconSize);
    });
  });

  group('schema versions', () {
    test('new boards are written with the current schema', () {
      expect(BoardDocument.create().toJson()['schemaVersion'], currentSchemaVersion);
    });

    test('schema 1 boards migrate unchanged', () {
      final json = BoardDocument.create(title: 'Old').toJson()..['schemaVersion'] = 1;
      final doc = BoardDocument.fromJson(json);
      expect(doc.title, 'Old');
      expect(doc.toJson()['schemaVersion'], currentSchemaVersion);
    });

    test('boards with components round-trip', () {
      final doc = BoardDocument(id: 'b', title: 'B', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026), objects: [component('c1')]);
      final back = BoardDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>);
      expect(back['c1'], isA<ComponentObject>());
    });
  });

  group('svg export', () {
    test('draws the card, icon and label', () {
      final doc = BoardDocument(id: 'b', title: 'B', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026), objects: [component('c1')]);
      final svg = exportSvg(doc);
      expect(svg, contains('<g transform="translate('));
      expect(svg, contains('Orders DB'));
      expect(svg, contains('<ellipse')); // database cylinder top
    });

    test('zones are dashed', () {
      final doc = BoardDocument(
        id: 'b',
        title: 'B',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        objects: [
          const ComponentObject(
            id: 'z',
            plugin: 'software-architecture',
            kind: 'system-boundary',
            position: Vec2.zero,
            size: Vec2(400, 300),
            label: 'Payments <core>',
            color: 0xFF4F46E5,
          ),
        ],
      );
      final svg = exportSvg(doc);
      expect(svg, contains('stroke-dasharray'));
      expect(svg, contains('Payments &lt;core&gt;'));
    });
  });
}
