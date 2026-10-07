import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';

/// A real, decodable PNG of [w] x [h] pixels.
Future<Uint8List> makePng(int w, int h, {Color color = const Color(0xFF4F46E5)}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = color);
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

BoardController newController() => BoardController(BoardDocument.create())..viewSize = const Size(800, 600);

void drag(BoardController c, Offset from, Offset to, {int steps = 8}) {
  c.pointerDown(from);
  for (var i = 1; i <= steps; i++) {
    c.pointerMove(Offset.lerp(from, to, i / steps)!);
  }
  c.pointerUp();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('inserting pictures', () {
    testWidgets('lands centered in the view, selected, shrunk if huge, named after the file', (tester) async {
      await tester.runAsync(() async {
        final c = newController();
        final ok = await c.insertImage(await makePng(2000, 1000), name: 'C:\\pics\\floor plan.png');
        expect(ok, isTrue);

        final img = c.document.objects.single as ImageObject;
        expect(c.selection, {img.id});
        expect(c.tool, Tool.select);
        expect(img.naturalSize, const Vec2(2000, 1000));
        expect(img.size.x, closeTo(800 * 0.7, 0.01)); // fits within 70% of the view
        expect(img.size.x / img.size.y, closeTo(2, 1e-6));
        expect(img.bounds.center.x, closeTo(400, 0.01));
        expect(img.bounds.center.y, closeTo(300, 0.01));
        expect(c.document.layerName(img.id), 'floor plan');
        expect(c.document.asset(img.assetId)!.mime, 'image/png');

        c.undo();
        expect(c.document.isEmpty, isTrue);
        c.redo();
        expect(c.document.length, 1);
        expect(c.document.layerName(img.id), 'floor plan');
      });
    });

    testWidgets('centers on what is visible after panning and zooming', (tester) async {
      await tester.runAsync(() async {
        final c = newController()..setCamera(const Camera(pan: Vec2(-1000, -500), zoom: 2));
        await c.insertImage(await makePng(50, 50));
        final img = c.document.objects.single as ImageObject;
        final centerOnScreen = c.toScreen(img.bounds.center);
        expect(centerOnScreen.dx, closeTo(400, 0.01));
        expect(centerOnScreen.dy, closeTo(300, 0.01));
        expect(img.size, const Vec2(50, 50)); // small pictures keep their size
      });
    });

    testWidgets('things that are not pictures are refused', (tester) async {
      await tester.runAsync(() async {
        final c = newController();
        expect(await c.insertImage(Uint8List.fromList(utf8.encode('plain text'))), isFalse);
        // Looks like a PNG but cannot be decoded.
        final broken = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
        expect(await c.insertImage(broken), isFalse);
        expect(c.document.isEmpty, isTrue);
      });
    });

    testWidgets('the same picture twice shares one asset', (tester) async {
      await tester.runAsync(() async {
        final c = newController();
        final png = await makePng(30, 30);
        await c.insertImage(png);
        await c.insertImage(png);
        expect(c.document.length, 2);
        expect(c.document.assets, hasLength(1));
      });
    });
  });

  group('pasting', () {
    testWidgets('a picture wins over text; text alone becomes a text object', (tester) async {
      await tester.runAsync(() async {
        final c = newController();
        c.clipboardReader = () async => ClipboardContent(text: 'https://x.test/a.png', images: [PastedImage(await makePng(40, 40))]);
        await c.paste();
        expect(c.document.objects.single, isA<ImageObject>());

        final d = newController();
        d.clipboardReader = () async => const ClipboardContent(text: 'hello board');
        await d.paste();
        expect((d.document.objects.single as TextObject).text, 'hello board');
      });
    });

    testWidgets('copied board objects keep working and beat pictures', (tester) async {
      await tester.runAsync(() async {
        final c = newController()..setTool(Tool.rectangle);
        drag(c, const Offset(0, 0), const Offset(60, 40));
        c.selectAll();
        final payload = c.copyPayload()!;
        c.clipboardReader = () async => ClipboardContent(text: payload, images: [PastedImage(await makePng(10, 10))]);
        await c.paste();
        expect(c.document.length, 2);
        expect(c.document.objects.whereType<ImageObject>(), isEmpty);
      });
    });

    testWidgets('several pictures are cascaded; an undecodable one falls back to the text', (tester) async {
      await tester.runAsync(() async {
        final c = newController();
        final a = await makePng(40, 40), b = await makePng(40, 41);
        await c.pasteContent(ClipboardContent(images: [PastedImage(a), PastedImage(b)]));
        final imgs = c.document.objects.whereType<ImageObject>().toList();
        expect(imgs, hasLength(2));
        expect(imgs[1].position.x - imgs[0].position.x, closeTo(24, 0.01));

        final d = newController();
        await d.pasteContent(ClipboardContent(text: 'fallback', images: [PastedImage(Uint8List.fromList([1, 2, 3]))]));
        expect((d.document.objects.single as TextObject).text, 'fallback');
      });
    });
  });

  group('drawing over a picture', () {
    /// A 400x300 picture at (100,100)..(500,400), plus the controller.
    Future<(BoardController, ImageObject)> boardWithPicture() async {
      final c = newController();
      await c.insertImage(await makePng(400, 300));
      var img = c.document.objects.single as ImageObject;
      // Pin it to known coordinates.
      final placed = img.copyWith(position: const Vec2(100, 100), size: const Vec2(400, 300));
      c.history.execute(UpdateObjects(before: [img], after: [placed]));
      img = placed;
      c.clearSelection();
      return (c, img);
    }

    testWidgets('pen and shapes draw on top without dragging the picture', (tester) async {
      await tester.runAsync(() async {
        final (c, img) = await boardWithPicture();
        c.setTool(Tool.pen);
        drag(c, const Offset(150, 150), const Offset(450, 350));
        c.setTool(Tool.rectangle);
        drag(c, const Offset(200, 200), const Offset(300, 260));

        expect((c.document[img.id]! as ImageObject).position, const Vec2(100, 100));
        expect(c.document.length, 3);
        expect(c.document.order.first, img.id); // the picture is below its annotations
        expect(c.document.objects.last, isA<ShapeObject>());
      });
    });

    testWidgets('drawing can be sent below the picture with layer order', (tester) async {
      await tester.runAsync(() async {
        final (c, img) = await boardWithPicture();
        c.setTool(Tool.pen);
        drag(c, const Offset(150, 150), const Offset(450, 350));
        final stroke = c.document.objects.last;
        c.selectLayer(stroke.id);
        c.reorderSelection(ZMove.backward);
        expect(c.document.order, [stroke.id, img.id]);
        c.undo();
        expect(c.document.order, [img.id, stroke.id]);
      });
    });

    testWidgets('a locked picture cannot be picked, moved or resized, so you can draw over it', (tester) async {
      await tester.runAsync(() async {
        final (c, img) = await boardWithPicture();
        c.setLayerLocked(img.id, true);

        // Select tool: dragging over it starts a marquee, not a move.
        drag(c, const Offset(200, 200), const Offset(260, 240));
        expect((c.document[img.id]! as ImageObject).position, const Vec2(100, 100));
        expect(c.selection, isEmpty);

        // Picked from the layers panel: selected, but no handles and no nudging or deleting.
        c.selectLayer(img.id);
        expect(c.selection, {img.id});
        expect(c.canTransformSelection, isFalse);
        expect(c.handlePositions(), isEmpty);
        c.nudge(const Vec2(10, 10));
        c.deleteSelection();
        expect(c.document.contains(img.id), isTrue);
        expect((c.document[img.id]! as ImageObject).position, const Vec2(100, 100));

        // Select all skips it; the eraser cannot remove it.
        c.selectAll();
        expect(c.selection, isEmpty);
        c.setTool(Tool.eraser);
        drag(c, const Offset(150, 250), const Offset(450, 250), steps: 20);
        expect(c.document.contains(img.id), isTrue);

        // Unlocked again: it moves like any other object.
        c.setLayerLocked(img.id, false);
        c.setTool(Tool.select);
        drag(c, const Offset(300, 250), const Offset(340, 270));
        expect((c.document[img.id]! as ImageObject).position, const Vec2(140, 120));
      });
    });

    testWidgets('moving and scaling with handles keeps the proportions', (tester) async {
      await tester.runAsync(() async {
        final (c, img) = await boardWithPicture();
        drag(c, const Offset(300, 250), const Offset(350, 280)); // move
        var now = c.document[img.id]! as ImageObject;
        expect(now.position, const Vec2(150, 130));
        expect(c.selection, {img.id});

        // Drag the bottom-right handle far to the right and only a little down.
        final handle = c.handlePositions()[Handle.bottomRight]!;
        drag(c, handle, handle + const Offset(200, 10));
        now = c.document[img.id]! as ImageObject;
        expect(now.size.x / now.size.y, closeTo(400 / 300, 1e-6));
        expect(now.size.x, greaterThan(400));
        expect(now.position, const Vec2(150, 130)); // anchored at the opposite corner
        c.undo();
        expect((c.document[img.id]! as ImageObject).size, const Vec2(400, 300));
      });
    });
  });

  group('layers', () {
    testWidgets('hide, show, rename, delete and reorder are undoable edits', (tester) async {
      await tester.runAsync(() async {
        final c = newController()..setTool(Tool.rectangle);
        drag(c, const Offset(0, 0), const Offset(50, 50));
        drag(c, const Offset(100, 0), const Offset(150, 50));
        drag(c, const Offset(200, 0), const Offset(250, 50));
        final [a, b, d] = c.document.order;

        c.selectLayer(b);
        c.setLayerVisible(b, false);
        expect(c.document.isVisible(b), isFalse);
        expect(c.selection, isEmpty); // a hidden layer cannot stay selected
        c.undo();
        expect(c.document.isVisible(b), isTrue);

        c.renameLayer(a, '  Header  ');
        expect(c.document.layerName(a), 'Header');
        c.renameLayer(a, '');
        expect(c.document.layerName(a), 'Rectangle');

        c.moveLayer(a, 2); // to the top
        expect(c.document.order, [b, d, a]);
        c.moveLayer(a, 0);
        expect(c.document.order, [a, b, d]);

        c.deleteLayer(b);
        expect(c.document.order, [a, d]);
        c.undo();
        expect(c.document.order, [a, b, d]);
      });
    });

    testWidgets('a no-op reorder does not create an undo step', (tester) async {
      final c = newController()..setTool(Tool.rectangle);
      drag(c, const Offset(0, 0), const Offset(50, 50));
      drag(c, const Offset(100, 0), const Offset(150, 50));
      c.selection.add(c.document.order.last);
      c.reorderSelection(ZMove.toFront);
      expect(c.history.undoLabel, 'Add rectangle');
    });

    testWidgets('] and [ move one step; Ctrl+] and Ctrl+[ go to the ends', (tester) async {
      final c = newController()..setTool(Tool.rectangle);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoardCanvas(controller: c))));
      await tester.pumpAndSettle();
      drag(c, const Offset(0, 0), const Offset(50, 50));
      drag(c, const Offset(100, 0), const Offset(150, 50));
      drag(c, const Offset(200, 0), const Offset(250, 50));
      final [a, b, d] = c.document.order;
      c.setTool(Tool.select);
      c.selectLayer(a);

      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      expect(c.document.order, [b, a, d]);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      expect(c.document.order, [a, b, d]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(c.document.order, [b, d, a]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(c.document.order, [a, b, d]);
    });
  });

  group('rendering', () {
    testWidgets('the canvas paints a picture and hides hidden layers', (tester) async {
      late BoardController c;
      await tester.runAsync(() async {
        c = newController();
        await c.insertImage(await makePng(120, 80));
      });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoardCanvas(controller: c))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.images.isReady((c.document.objects.single as ImageObject).assetId), isTrue);

      c.setLayerVisible(c.document.order.single, false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('PNG export contains pictures and skips hidden layers', (tester) async {
      await tester.runAsync(() async {
        final c = newController();
        await c.insertImage(await makePng(100, 50));
        final img = c.document.objects.single as ImageObject;
        final plain = c.document.objects.single.bounds;

        final png = await exportPng(c.document, pixelRatio: 1, padding: 10);
        expect(BoardAsset.sniffImageMime(png), 'image/png');
        final codec = await ui.instantiateImageCodec(png);
        final frame = (await codec.getNextFrame()).image;
        expect(frame.width, (plain.width + 20).ceil());
        expect(frame.height, (plain.height + 20).ceil());
        // The centre pixel is the picture's colour, not the board background.
        final bytes = (await frame.toByteData())!;
        final o = ((frame.height ~/ 2) * frame.width + frame.width ~/ 2) * 4;
        expect([bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)], [0x4F, 0x46, 0xE5]);
        frame.dispose();

        // Hidden: nothing to draw, so the export falls back to the empty-board frame.
        c.setLayerVisible(img.id, false);
        final empty = await exportPng(c.document, pixelRatio: 1, padding: 10);
        final emptyFrame = (await (await ui.instantiateImageCodec(empty)).getNextFrame()).image;
        expect(emptyFrame.width, 820);
        emptyFrame.dispose();
      });
    });

    testWidgets('thumbnails render for every kind of object', (tester) async {
      late BoardController c;
      await tester.runAsync(() async {
        c = newController()..setTool(Tool.rectangle);
        drag(c, const Offset(0, 0), const Offset(60, 40));
        c.setTool(Tool.pen);
        drag(c, const Offset(0, 100), const Offset(80, 140));
        await c.insertImage(await makePng(60, 30));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(children: [for (final o in c.document.objects) ObjectThumbnail(object: o, images: c.images)]),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ObjectThumbnail), findsNWidgets(3));
    });
  });
}
