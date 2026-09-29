// Seeds a demo board into $LOCAL_BOARD_DATA_DIR for screenshots / smoke tests.
// Run from the repo root: dart run tool/seed_demo.dart
import 'dart:io';

import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

Future<void> main() async {
  final store = BoardStore(defaultDataDirectory());
  final doc = BoardDocument.create(title: 'Launch plan');
  const ink = 0xFF17181A, accent = 0xFF4F46E5;
  final labels = ['Idea', 'Sketch', 'Review', 'Share'];
  final objects = <BoardObject>[
    const TextObject(id: 'title', position: Vec2(0, -150), text: 'Launch workshop', fontSize: 40, color: ink, size: Vec2(330, 52)),
    for (var i = 0; i < 4; i++) ...[
      ShapeObject(
        id: 'box$i',
        kind: ShapeKind.rectangle,
        start: Vec2(i * 240.0, 0),
        end: Vec2(i * 240.0 + 180, 72),
        strokeColor: ink,
        strokeWidth: 2,
        fillColor: 0xFFFFFFFF,
      ),
      TextObject(
        id: 'lbl$i',
        position: Vec2(i * 240.0 + 24, 20),
        text: labels[i],
        fontSize: 24,
        color: ink,
        size: const Vec2(120, 32),
      ),
      if (i < 3)
        ShapeObject(
          id: 'arr$i',
          kind: ShapeKind.arrow,
          start: Vec2(i * 240.0 + 188, 36),
          end: Vec2(i * 240.0 + 232, 36),
          strokeColor: ink,
          strokeWidth: 2,
        ),
    ],
    const StickyNote(id: 'n1', position: Vec2(-40, 150), size: Vec2(200, 170), text: 'Works with Wi-Fi off ✓', color: 0xFFFFE08A),
    const StickyNote(id: 'n2', position: Vec2(760, 150), size: Vec2(200, 170), text: 'Send to the team as PDF', color: 0xFFBFD7FF),
    const ShapeObject(
      id: 'circle',
      kind: ShapeKind.ellipse,
      start: Vec2(230, -24),
      end: Vec2(430, 96),
      strokeColor: accent,
      strokeWidth: 4,
    ),
    StrokeObject(
      id: 'squiggle',
      color: accent,
      width: 4,
      points: [for (var i = 0; i <= 60; i++) Vec2(300 + i * 5.0, 220 + 18 * (i % 12 < 6 ? (i % 6) : 6 - (i % 6)) / 6)],
    ),
    const TextObject(id: 'foot', position: Vec2(300, 260), text: 'draft 3 — saved locally', fontSize: 16, color: 0xFF55585E, size: Vec2(190, 22)),
  ];
  History(doc).execute(AddObjects(objects));
  await store.save(doc);
  await store.setLastOpened(doc.id);
  stdout.writeln('Seeded ${doc.id} into ${store.root.path}');
}
