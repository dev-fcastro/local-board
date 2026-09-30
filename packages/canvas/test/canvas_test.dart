import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';

BoardController newController() {
  final c = BoardController(BoardDocument.create())..viewSize = const Size(800, 600);
  return c;
}

void drag(BoardController c, Offset from, Offset to, {int steps = 8, bool shift = false}) {
  c.pointerDown(from, shift: shift);
  for (var i = 1; i <= steps; i++) {
    c.pointerMove(Offset.lerp(from, to, i / steps)!, shift: shift);
  }
  c.pointerUp();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardController', () {
    test('pen draws one stroke per drag, undo removes it', () {
      final c = newController()..setTool(Tool.pen);
      drag(c, const Offset(10, 10), const Offset(100, 60));
      expect(c.document.length, 1);
      final s = c.document.objects.first as StrokeObject;
      expect(s.points.length, greaterThan(2));
      c.undo();
      expect(c.document.isEmpty, isTrue);
      c.redo();
      expect(c.document.length, 1);
    });

    test('shapes: rectangle, ellipse, line, arrow; tiny drags are ignored', () {
      final c = newController();
      for (final t in [Tool.rectangle, Tool.ellipse, Tool.line, Tool.arrow]) {
        c.setTool(t);
        drag(c, const Offset(0, 0), const Offset(120, 80));
      }
      c.setTool(Tool.rectangle);
      drag(c, const Offset(300, 300), const Offset(301, 301));
      expect(c.document.length, 4);
      expect(
        c.document.objects.map((o) => (o as ShapeObject).kind),
        [ShapeKind.rectangle, ShapeKind.ellipse, ShapeKind.line, ShapeKind.arrow],
      );
    });

    test('shift makes squares', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, Offset.zero, const Offset(100, 40), shift: true);
      final r = c.document.objects.first.bounds.inflate(-c.strokeWidth / 2);
      expect(r.width, closeTo(r.height, 0.01));
    });

    test('screen input respects pan and zoom', () {
      final c = newController()
        ..setCamera(const Camera(pan: Vec2(100, 50), zoom: 2))
        ..setTool(Tool.rectangle);
      drag(c, const Offset(100, 50), const Offset(300, 250));
      final s = c.document.objects.first as ShapeObject;
      expect(s.start, Vec2.zero);
      expect(s.end, const Vec2(100, 100));
    });

    test('select + move is one undo step, identity preserved', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, const Offset(0, 0), const Offset(100, 100));
      final id = c.document.objects.first.id;
      c.setTool(Tool.select);
      drag(c, const Offset(0, 50), const Offset(40, 90)); // grab the left edge
      final moved = c.document[id]! as ShapeObject;
      expect(moved.start, const Vec2(40, 40));
      c.undo();
      expect((c.document[id]! as ShapeObject).start, Vec2.zero);
    });

    test('marquee selects enclosed objects only', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, const Offset(10, 10), const Offset(50, 50));
      drag(c, const Offset(200, 200), const Offset(400, 400));
      c.setTool(Tool.select);
      drag(c, const Offset(0, 0), const Offset(100, 100));
      expect(c.selection.length, 1);
    });

    test('resize from the bottom-right handle', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, const Offset(0, 0), const Offset(100, 100));
      c.setTool(Tool.select);
      c.selectAll();
      final handle = c.handlePositions()[Handle.bottomRight]!;
      drag(c, handle, handle + const Offset(100, 100));
      final b = c.document.objects.first.bounds;
      expect(b.width, greaterThan(180));
      c.undo();
      expect(c.document.objects.first.bounds.width, lessThan(110));
    });

    test('eraser removes what it touches in one undoable step', () {
      final c = newController()..setTool(Tool.line);
      drag(c, const Offset(0, 50), const Offset(200, 50));
      drag(c, const Offset(0, 150), const Offset(200, 150));
      drag(c, const Offset(0, 300), const Offset(200, 300));
      c.setTool(Tool.eraser);
      drag(c, const Offset(100, 0), const Offset(100, 200), steps: 40);
      expect(c.document.length, 1);
      c.undo();
      expect(c.document.length, 3);
    });

    test('delete, select all, duplicate, reorder', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, const Offset(0, 0), const Offset(50, 50));
      drag(c, const Offset(100, 0), const Offset(150, 50));
      c.selectAll();
      c.duplicateSelection();
      expect(c.document.length, 4);
      expect(c.selection.length, 2);
      c.deleteSelection();
      expect(c.document.length, 2);
      final first = c.document.order.first;
      c.selection
        ..clear()
        ..add(first);
      c.reorderSelection(ZMove.toFront);
      expect(c.document.order.last, first);
    });

    test('text: create, edit, empty edit deletes', () {
      final c = newController()..setTool(Tool.text);
      c.pointerDown(const Offset(100, 100));
      c.pointerUp();
      expect(c.editing, isNotNull);
      c.commitEdit('Hello');
      final t = c.document.objects.single as TextObject;
      expect(t.text, 'Hello');
      expect(t.size.x, greaterThan(0));

      c.beginEditObject(t);
      c.commitEdit('Hello world');
      expect((c.document[t.id]! as TextObject).text, 'Hello world');

      c.beginEditObject(c.document[t.id]!);
      c.commitEdit('   ');
      expect(c.document.isEmpty, isTrue);
      c.undo();
      expect(c.document.length, 1);
    });

    test('empty new text creates nothing', () {
      final c = newController()..setTool(Tool.text);
      c.pointerDown(const Offset(100, 100));
      c.pointerUp();
      c.commitEdit('');
      expect(c.document.isEmpty, isTrue);
      expect(c.canUndo, isFalse);
    });

    test('sticky notes are created even when empty and keep their color', () {
      final c = newController()
        ..setStickyColor(Palette.stickies[2])
        ..setTool(Tool.sticky);
      c.pointerDown(const Offset(300, 300));
      c.pointerUp();
      c.commitEdit('');
      final n = c.document.objects.single as StickyNote;
      expect(n.color, Palette.stickies[2]);
    });

    test('style changes apply to the selection as one undo step each', () {
      final c = newController()..setTool(Tool.pen);
      drag(c, Offset.zero, const Offset(50, 50));
      c.selectAll();
      c.setColor(Palette.accent);
      c.setStrokeWidth(8);
      final s = c.document.objects.first as StrokeObject;
      expect(s.color, Palette.accent);
      expect(s.width, 8);
      c.undo();
      expect((c.document.objects.first as StrokeObject).width, isNot(8));
    });

    test('copy payload pastes as new objects at the cursor', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, Offset.zero, const Offset(100, 100));
      c.selectAll();
      final payload = c.copyPayload()!;
      c.hoverScreen = const Offset(500, 500);
      c.pasteText(payload);
      expect(c.document.length, 2);
      final pasted = c.selectedObjects.single;
      expect(pasted.id, isNot(c.document.order.first));
      expect(pasted.bounds.center.x, closeTo(500, 0.01));
    });

    test('plain text pastes as a text object', () {
      final c = newController();
      c.pasteText('from another app');
      expect((c.document.objects.single as TextObject).text, 'from another app');
    });

    test('wheel zoom keeps the point under the cursor', () {
      final c = newController();
      const cursor = Offset(320, 240);
      final before = c.toWorld(cursor);
      c.scroll(cursor, const Offset(0, -200));
      expect(c.camera.zoom, greaterThan(1));
      final after = c.toWorld(cursor);
      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
    });

    test('camera changes are not undo steps', () {
      final c = newController()..panBy(const Offset(30, 30));
      c.zoomBy(2);
      expect(c.canUndo, isFalse);
      expect(c.document.revision, 0);
    });

    test('zoom to fit frames the content', () {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, const Offset(0, 0), const Offset(2000, 100), steps: 2);
      c.zoomToFit();
      final b = c.document.contentBounds!;
      final tl = c.toScreen(b.topLeft);
      expect(tl.dx, greaterThanOrEqualTo(0));
      expect(c.toScreen(Vec2(b.right, b.bottom)).dx, lessThanOrEqualTo(800));
    });

    test('middle mouse pans in any tool', () {
      final c = newController()..setTool(Tool.pen);
      c.pointerDown(const Offset(100, 100), buttons: kMiddleMouseButton);
      c.pointerMove(const Offset(150, 120));
      c.pointerUp();
      expect(c.camera.pan, const Vec2(50, 20));
      expect(c.document.isEmpty, isTrue);
    });
  });

  group('BoardCanvas widget', () {
    testWidgets('draws with the mouse and handles shortcuts', (tester) async {
      final c = BoardController(BoardDocument.create());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoardCanvas(controller: c))));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(c.tool, Tool.rectangle);

      final g = await tester.startGesture(const Offset(100, 100), kind: PointerDeviceKind.mouse);
      await g.moveTo(const Offset(200, 180));
      await g.moveTo(const Offset(300, 260));
      await g.up();
      await tester.pump();
      expect(c.document.length, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.document.isEmpty, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.document.length, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.document.isEmpty, isTrue);
    });

    testWidgets('typing text through the in-place editor', (tester) async {
      final c = BoardController(BoardDocument.create());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoardCanvas(controller: c))));
      await tester.pumpAndSettle();

      c.setTool(Tool.text);
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Plan A');
      // Typing letters must not switch tools.
      expect(c.tool, Tool.text);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect((c.document.objects.single as TextObject).text, 'Plan A');
    });
  });

  test('PNG export produces a valid image', () async {
    final c = newController()..setTool(Tool.rectangle);
    drag(c, Offset.zero, const Offset(100, 50));
    final bytes = await exportPng(c.document, pixelRatio: 1);
    expect(bytes.sublist(0, 8), Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
  });

  group('plugin components', () {
    test('armed component follows the cursor, a click places it and opens its name', () {
      final c = newController();
      final kind = softwareArchitecturePlugin.kind('database')!;
      c.armComponent(softwareArchitecturePlugin, kind);
      expect(c.tool, Tool.component);
      c.pointerHover(const Offset(300, 200));
      expect(c.draft, isA<ComponentObject>());
      c.pointerDown(const Offset(300, 200));
      c.pointerUp();
      expect(c.document.length, 1);
      final placed = c.document.objects.first as ComponentObject;
      expect(placed.kind, 'database');
      expect(placed.label, 'Database');
      expect(placed.bounds.center, c.toWorld(const Offset(300, 200)));
      expect(c.tool, Tool.select);
      expect(c.editing?.isLabel, isTrue);
      c.commitEdit('  Orders DB ');
      expect((c.document.objects.first as ComponentObject).label, 'Orders DB');
      c.undo();
      expect((c.document.objects.first as ComponentObject).label, 'Database');
      c.undo();
      expect(c.document.isEmpty, isTrue);
    });

    test('zones go behind what is already on the board', () {
      final c = newController()..setTool(Tool.sticky);
      c.pointerDown(const Offset(100, 100));
      c.commitEdit('note');
      c.armComponent(networkArchitecturePlugin, networkArchitecturePlugin.kind('network-zone')!);
      c.pointerDown(const Offset(200, 200));
      c.pointerUp();
      c.commitEdit('DMZ');
      expect(c.document.objects.first, isA<ComponentObject>());
      expect(c.document.objects.last, isA<StickyNote>());
    });

    test('color changes recolor selected components', () {
      final c = newController();
      c.armComponent(softwareArchitecturePlugin, softwareArchitecturePlugin.kinds.first);
      c.pointerDown(const Offset(300, 200));
      c.pointerUp();
      c.commitEdit('User');
      c.setColor(Palette.inks.last);
      expect((c.document.objects.first as ComponentObject).color, Palette.inks.last);
    });

    testWidgets('components paint on the canvas', (tester) async {
      final c = newController();
      c.armComponent(networkArchitecturePlugin, networkArchitecturePlugin.kind('router')!);
      c.pointerDown(const Offset(300, 200));
      c.pointerUp();
      c.commitEdit('Edge router');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoardCanvas(controller: c))));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
