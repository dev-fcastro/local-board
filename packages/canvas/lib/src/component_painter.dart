import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:local_board_core/local_board_core.dart';

import 'text_layout.dart';

/// Icons and labels are immutable, so identity is the cache key (same as the
/// board painter's caches).
final Expando<(Path, Path)> _iconCache = Expando('icon');
final Expando<TextPainter> _labelCache = Expando('label');

Rect _rect(Bounds b) => Rect.fromLTRB(b.left, b.top, b.right, b.bottom);

/// Stroked and filled outlines of [icon] on its 24×24 grid.
(Path, Path) _iconPaths(ComponentIcon icon) => _iconCache[icon] ??= () {
  final stroke = Path(), fill = Path();
  for (final part in icon.parts) {
    final target = part.filled ? fill : stroke;
    switch (part) {
      case IconLine l:
        target
          ..moveTo(l.x1, l.y1)
          ..lineTo(l.x2, l.y2);
      case IconRect r:
        target.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.x, r.y, r.width, r.height), Radius.circular(r.radius)));
      case IconCircle c:
        target.addOval(Rect.fromCircle(center: Offset(c.cx, c.cy), radius: c.r));
      case IconEllipse e:
        target.addOval(Rect.fromCenter(center: Offset(e.cx, e.cy), width: e.rx * 2, height: e.ry * 2));
      case IconPolyline p:
        target.addPolygon([
          for (var i = 0; i + 1 < p.points.length; i += 2) Offset(p.points[i], p.points[i + 1]),
        ], p.closed);
      case IconPath p:
        final sub = Path();
        for (final s in parseIconPath(p.data)) {
          switch (s) {
            case MoveTo(:final x, :final y):
              sub.moveTo(x, y);
            case LineTo(:final x, :final y):
              sub.lineTo(x, y);
            case CubicTo c:
              sub.cubicTo(c.x1, c.y1, c.x2, c.y2, c.x, c.y);
            case ClosePath():
              sub.close();
          }
        }
        target.addPath(sub, Offset.zero);
    }
  }
  return (stroke, fill);
}();

/// Draws [icon] scaled into [box]. Also used by the component library.
void paintComponentIcon(Canvas canvas, ComponentIcon icon, Rect box, Color color) {
  final (stroke, fill) = _iconPaths(icon);
  canvas.save();
  canvas.translate(box.left, box.top);
  canvas.scale(box.width / ComponentIcon.grid);
  canvas.drawPath(
    stroke,
    Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = ComponentIcon.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(fill, Paint()..color = color);
  canvas.restore();
}

TextStyle componentLabelStyle(ComponentObject c) => boardTextStyle(
  ComponentStyle.labelFontSize,
  c.isZone ? c.color : ComponentStyle.labelColor,
).copyWith(fontWeight: c.isZone ? FontWeight.w600 : FontWeight.w500);

TextPainter _label(ComponentObject c, Bounds box) => _labelCache[c] ??= TextPainter(
  text: TextSpan(text: c.label, style: componentLabelStyle(c)),
  textDirection: TextDirection.ltr,
  textAlign: c.isZone ? TextAlign.left : TextAlign.center,
  ellipsis: '…',
  maxLines: c.isZone ? 1 : ComponentStyle.labelLines,
)..layout(minWidth: c.isZone ? 0 : math.max(1, box.width), maxWidth: math.max(1, box.width));

void paintComponent(Canvas canvas, ComponentObject c, {bool showLabel = true}) {
  final r = _rect(c.bounds);
  final layout = ComponentLayout.of(c);
  if (c.isZone) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(ComponentStyle.zoneRadius));
    canvas.drawRRect(rr, Paint()..color = Color(ComponentStyle.zoneFill(c.color)));
    canvas.drawPath(
      _dashed(Path()..addRRect(rr), ComponentStyle.zoneDash, ComponentStyle.zoneGap),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color(c.color)
        ..strokeWidth = ComponentStyle.borderWidth,
    );
  } else {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(ComponentStyle.cardRadius));
    canvas.drawRRect(
      rr.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x14000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(rr, Paint()..color = const Color(ComponentStyle.cardFill));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color(ComponentStyle.border(c.color))
        ..strokeWidth = ComponentStyle.borderWidth,
    );
  }
  paintComponentIcon(canvas, c.icon, _rect(layout.icon), Color(c.color));
  if (!showLabel || c.label.isEmpty) return;
  final box = layout.label;
  final tp = _label(c, box);
  final y = box.center.y - tp.height / 2;
  tp.paint(canvas, Offset(box.left, c.isZone ? y : math.max(box.top, y)));
}

Path _dashed(Path source, double dash, double gap) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}
