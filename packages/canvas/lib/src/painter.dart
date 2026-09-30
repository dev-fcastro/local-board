import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:local_board_core/local_board_core.dart';

import 'component_painter.dart';
import 'palette.dart';
import 'text_layout.dart';

/// Per-object render caches. Objects are immutable, so identity is a perfect
/// cache key: an edit produces a new object and the old entry is collected.
final Expando<Path> _pathCache = Expando('path');
final Expando<TextPainter> _textCache = Expando('text');

Path strokePath(StrokeObject s) => _pathCache[s] ??= _buildStrokePath(s.points);

Path _buildStrokePath(List<Vec2> pts) {
  final path = Path()..moveTo(pts[0].x, pts[0].y);
  if (pts.length == 1) return path..lineTo(pts[0].x + 0.01, pts[0].y);
  // Same curve as core's strokePathData(), so SVG export matches the screen.
  for (var i = 1; i < pts.length - 1; i++) {
    final mx = (pts[i].x + pts[i + 1].x) / 2, my = (pts[i].y + pts[i + 1].y) / 2;
    path.quadraticBezierTo(pts[i].x, pts[i].y, mx, my);
  }
  return path..lineTo(pts.last.x, pts.last.y);
}

TextPainter _textPainter(BoardObject o) => _textCache[o] ??= switch (o) {
  TextObject t => TextPainter(
    text: TextSpan(text: t.text, style: boardTextStyle(t.fontSize, t.color)),
    textDirection: TextDirection.ltr,
  )..layout(),
  StickyNote n => TextPainter(
    text: TextSpan(text: n.text, style: boardTextStyle(BoardStyle.stickyFontSize, Palette.ink)),
    textDirection: TextDirection.ltr,
    ellipsis: '…',
    maxLines: math.max(1, ((n.size.y - BoardStyle.stickyPadding * 2) / (BoardStyle.stickyFontSize * BoardStyle.lineHeight)).floor()),
  )..layout(maxWidth: math.max(1, n.size.x - BoardStyle.stickyPadding * 2)),
  _ => throw ArgumentError('No text for ${o.type}'),
};

/// Draws one object in world coordinates. Shared by the canvas and PNG export.
void paintObject(Canvas canvas, BoardObject o, {double opacity = 1, bool showLabel = true}) {
  final layer = opacity < 1;
  if (layer) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
  switch (o) {
    case StrokeObject s:
      canvas.drawPath(
        strokePath(s),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Color(s.color)
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    case ShapeObject s:
      _paintShape(canvas, s);
    case TextObject t:
      _textPainter(t).paint(canvas, Offset(t.position.x, t.position.y));
    case StickyNote n:
      final r = Rect.fromLTWH(n.position.x, n.position.y, n.size.x, n.size.y);
      canvas.drawRect(
        r.shift(const Offset(0, 3)),
        Paint()
          ..color = const Color(0x1A000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = Color(n.color));
      if (n.text.isNotEmpty) {
        _textPainter(n).paint(canvas, r.topLeft + const Offset(BoardStyle.stickyPadding, BoardStyle.stickyPadding));
      }
    case ComponentObject c:
      paintComponent(canvas, c, showLabel: showLabel);
  }
  if (layer) canvas.restore();
}

void _paintShape(Canvas canvas, ShapeObject s) {
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..color = Color(s.strokeColor)
    ..strokeWidth = s.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final rect = Rect.fromPoints(Offset(s.start.x, s.start.y), Offset(s.end.x, s.end.y));
  switch (s.kind) {
    case ShapeKind.rectangle:
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      if (s.fillColor != null) canvas.drawRRect(rr, Paint()..color = Color(s.fillColor!));
      canvas.drawRRect(rr, stroke);
    case ShapeKind.ellipse:
      if (s.fillColor != null) canvas.drawOval(rect, Paint()..color = Color(s.fillColor!));
      canvas.drawOval(rect, stroke);
    case ShapeKind.line:
    case ShapeKind.arrow:
      final a = Offset(s.start.x, s.start.y), b = Offset(s.end.x, s.end.y);
      canvas.drawLine(a, b, stroke);
      if (s.kind == ShapeKind.arrow && (b - a).distance > 0.5) {
        final (w1, w2) = arrowHead(s.start, s.end, s.strokeWidth);
        canvas.drawPath(
          Path()
            ..moveTo(w1.x, w1.y)
            ..lineTo(b.dx, b.dy)
            ..lineTo(w2.x, w2.y),
          stroke,
        );
      }
  }
}

/// What the board painter needs for one frame.
final class BoardScene {
  const BoardScene({
    required this.document,
    required this.viewport,
    this.preview = const {},
    this.erasing = const {},
    this.hidden,
    this.blankLabel,
    this.draft,
    this.selection = const {},
    this.selectionBounds,
    this.marquee,
    this.showHandles = true,
  });

  final BoardDocument document;
  final Camera viewport;
  final Map<String, BoardObject> preview;
  final Set<String> erasing;
  final String? hidden;

  /// Component whose label is being edited in place (drawn without it).
  final String? blankLabel;
  final BoardObject? draft;
  final Set<String> selection;
  final Bounds? selectionBounds;
  final Bounds? marquee;
  final bool showHandles;
}

class BoardPainter extends CustomPainter {
  BoardPainter(this.scene, {super.repaint});

  final BoardScene scene;

  static const _selectionColor = Color(Palette.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final v = scene.viewport;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Palette.canvas));
    _paintGrid(canvas, size, v);

    final visible = Bounds(
      -v.pan.x / v.zoom,
      -v.pan.y / v.zoom,
      (size.width - v.pan.x) / v.zoom,
      (size.height - v.pan.y) / v.zoom,
    ).inflate(20 / v.zoom);

    canvas.save();
    canvas.translate(v.pan.x, v.pan.y);
    canvas.scale(v.zoom);

    for (final original in scene.document.objects) {
      if (original.id == scene.hidden) continue;
      final o = scene.preview[original.id] ?? original;
      if (!visible.overlaps(o.bounds)) continue; // culling keeps big boards fast
      paintObject(canvas, o, opacity: scene.erasing.contains(o.id) ? 0.25 : 1, showLabel: o.id != scene.blankLabel);
    }
    final draft = scene.draft;
    if (draft != null) paintObject(canvas, draft, opacity: draft is ComponentObject ? 0.55 : 1);

    final hairline = 1 / v.zoom;
    if (scene.selection.isNotEmpty) {
      final sel = Paint()
        ..style = PaintingStyle.stroke
        ..color = _selectionColor.withValues(alpha: 0.55)
        ..strokeWidth = hairline;
      for (final id in scene.selection) {
        final o = scene.preview[id] ?? scene.document[id];
        if (o == null) continue;
        canvas.drawRect(_rect(o.bounds.inflate(2 / v.zoom)), sel);
      }
    }

    final m = scene.marquee;
    if (m != null) {
      canvas.drawRect(_rect(m), Paint()..color = _selectionColor.withValues(alpha: 0.08));
      canvas.drawRect(
        _rect(m),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _selectionColor
          ..strokeWidth = hairline,
      );
    }
    canvas.restore();

    // Handles are drawn in screen space so they stay the same size at any zoom.
    final b = scene.selectionBounds;
    if (b != null && scene.showHandles) {
      final tl = v.toScreen(b.topLeft), br = v.toScreen(Vec2(b.right, b.bottom));
      final frame = Rect.fromLTRB(tl.x - 4, tl.y - 4, br.x + 4, br.y + 4);
      canvas.drawRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _selectionColor
          ..strokeWidth = 1.2,
      );
      for (final c in [frame.topLeft, frame.topRight, frame.bottomLeft, frame.bottomRight]) {
        final r = Rect.fromCenter(center: c, width: 9, height: 9);
        canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _selectionColor
            ..strokeWidth = 1.2,
        );
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size, Camera v) {
    // Dot grid that thins out as you zoom away, like the site mockup.
    var spacing = 24 * v.zoom;
    while (spacing < 14) {
      spacing *= 2;
    }
    final ox = v.pan.x % spacing, oy = v.pan.y % spacing;
    final pts = <Offset>[];
    for (var x = ox; x < size.width; x += spacing) {
      for (var y = oy; y < size.height; y += spacing) {
        pts.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = const Color(Palette.gridDot)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  Rect _rect(Bounds b) => Rect.fromLTRB(b.left, b.top, b.right, b.bottom);

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}
