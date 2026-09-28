import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_board/src/app.dart';
import 'package:local_board/src/widgets.dart';
import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

/// v0.1 definition of done (plan §25), end to end through the real UI:
/// open the app, create a board, draw, undo, close, reopen, same state.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('lb_app_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Real file I/O only completes outside the test's fake clock, and every
  /// await in a chain needs its own turn. Pump until [until] shows up.
  Future<void> settleIo(WidgetTester tester, {Finder? until}) async {
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
      if (until != null && until.evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> pumpApp(WidgetTester tester, BoardStore store) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LocalBoardApp(store: store));
    // Home is ready once the board list has loaded (empty state or grid).
    await settleIo(
      tester,
      until: find.byWidgetPredicate(
        (w) => w is GridView || (w is Text && w.data == 'Your boards live here.'),
      ),
    );
  }

  testWidgets('create, draw, undo, autosave, reopen', (tester) async {
    final store = BoardStore(dir);
    await pumpApp(tester, store);

    expect(find.text('Your boards live here.'), findsOneWidget);
    await tester.tap(find.text('Create your first board'));
    await settleIo(tester, until: find.text('Untitled board'));
    expect(find.text('Untitled board'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    // Draw two rectangles with the keyboard shortcut + mouse.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    for (final start in [const Offset(400, 300), const Offset(700, 300)]) {
      final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await g.moveTo(start + const Offset(60, 40));
      await g.moveTo(start + const Offset(150, 100));
      await g.up();
      await tester.pump();
    }

    // Undo the second one.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Leave the editor (flushes autosave) and check what hit the disk.
    await tester.tap(find.byTooltip('All boards (Ctrl+W)'));
    await settleIo(tester, until: find.textContaining('1 item'));

    final boards = await tester.runAsync(store.list);
    expect(boards, hasLength(1));
    final onDisk = (await tester.runAsync(() => store.open(boards!.single.id)))!.document;
    expect(onDisk.length, 1);
    expect((onDisk.objects.single as ShapeObject).kind, ShapeKind.rectangle);

    // Home lists it with its item count.
    expect(find.textContaining('1 item'), findsOneWidget);

    // "Restart" the app: a fresh store on the same folder reopens the list
    // and the board with the same content.
    await tester.pumpWidget(const SizedBox());
    final store2 = BoardStore(dir);
    await pumpApp(tester, store2);
    await tester.tap(find.text('Untitled board'));
    await settleIo(tester, until: find.text('Saved'));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byTooltip('All boards (Ctrl+W)'), findsOneWidget);

    // Close the app and let pending writes finish: Windows cannot delete the
    // temp folder while a save still has a file open.
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });

  test('relative time labels', () {
    final now = DateTime.utc(2026, 9, 28, 12);
    expect(relativeTime(now.subtract(const Duration(seconds: 5)), now: now), 'Just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(relativeTime(now.subtract(const Duration(days: 1, hours: 2)), now: now), 'Yesterday');
  });
}
