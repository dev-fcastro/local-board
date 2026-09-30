import 'dart:math' as math;

import 'document.dart';
import 'geometry.dart';
import 'objects.dart';
import 'plugins/component_layout.dart';
import 'plugins/plugin.dart';

/// Visual constants shared by the Flutter renderer and the SVG exporter so a
/// board looks the same in the app and outside it.
abstract final class BoardStyle {
  static const background = 0xFFFAF9F9;
  static const stickyFontSize = 20.0;
  static const stickyPadding = 16.0;
  static const lineHeight = 1.3;
  static const fontFamily = 'Space Grotesk';
}

/// Smooth stroke outline as quadratic segments through point midpoints.
/// Returns SVG path data; the Flutter painter mirrors the same curve.
String strokePathData(List<Vec2> pts) {
  String f(double v) => v.toStringAsFixed(2);
  if (pts.isEmpty) return '';
  final b = StringBuffer('M${f(pts[0].x)} ${f(pts[0].y)}');
  if (pts.length == 1) {
    b.write(' L${f(pts[0].x + 0.01)} ${f(pts[0].y)}');
    return b.toString();
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = Vec2((pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2);
    b.write(' Q${f(pts[i].x)} ${f(pts[i].y)} ${f(mid.x)} ${f(mid.y)}');
  }
  b.write(' L${f(pts.last.x)} ${f(pts.last.y)}');
  return b.toString();
}

/// The two wing points of an arrow head at [end].
(Vec2, Vec2) arrowHead(Vec2 start, Vec2 end, double strokeWidth) {
  final len = ShapeObject.arrowHeadLength(strokeWidth);
  final angle = math.atan2(end.y - start.y, end.x - start.x);
  const spread = math.pi / 7;
  return (
    Vec2(end.x - len * math.cos(angle - spread), end.y - len * math.sin(angle - spread)),
    Vec2(end.x - len * math.cos(angle + spread), end.y - len * math.sin(angle + spread)),
  );
}

/// Exports a board to a standalone SVG string (plan §14). Works offline and
/// needs no Flutter.
String exportSvg(BoardDocument doc, {double padding = 32, bool background = true}) {
  final content = doc.contentBounds ?? const Bounds(0, 0, 800, 600);
  final box = content.inflate(padding);
  String f(double v) => v.toStringAsFixed(2);
  String rgb(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  String alpha(int c) => (((c >> 24) & 0xFF) / 255).toStringAsFixed(3);
  String paint(String attr, int c) {
    final a = (c >> 24) & 0xFF;
    return a == 0xFF ? '$attr="${rgb(c)}"' : '$attr="${rgb(c)}" $attr-opacity="${alpha(c)}"';
  }

  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${f(box.width)}" height="${f(box.height)}" '
      'viewBox="${f(box.left)} ${f(box.top)} ${f(box.width)} ${f(box.height)}">',
    )
    ..writeln('<title>${_escape(doc.title)}</title>');
  if (background) {
    out.writeln(
      '<rect x="${f(box.left)}" y="${f(box.top)}" width="${f(box.width)}" height="${f(box.height)}" '
      '${paint('fill', BoardStyle.background)}/>',
    );
  }
  const font = 'font-family="${BoardStyle.fontFamily}, system-ui, sans-serif"';

  for (final o in doc.objects) {
    switch (o) {
      case StrokeObject s:
        out.writeln(
          '<path d="${strokePathData(s.points)}" fill="none" ${paint('stroke', s.color)} '
          'stroke-width="${f(s.width)}" stroke-linecap="round" stroke-linejoin="round"/>',
        );
      case ShapeObject s:
        final stroke = '${paint('stroke', s.strokeColor)} stroke-width="${f(s.strokeWidth)}"';
        final fill = s.fillColor == null ? 'fill="none"' : paint('fill', s.fillColor!);
        final r = Bounds.fromPoints(s.start, s.end);
        switch (s.kind) {
          case ShapeKind.rectangle:
            out.writeln(
              '<rect x="${f(r.left)}" y="${f(r.top)}" width="${f(r.width)}" height="${f(r.height)}" '
              'rx="4" $fill $stroke stroke-linejoin="round"/>',
            );
          case ShapeKind.ellipse:
            out.writeln(
              '<ellipse cx="${f(r.center.x)}" cy="${f(r.center.y)}" rx="${f(r.width / 2)}" ry="${f(r.height / 2)}" '
              '$fill $stroke/>',
            );
          case ShapeKind.line:
          case ShapeKind.arrow:
            out.writeln(
              '<line x1="${f(s.start.x)}" y1="${f(s.start.y)}" x2="${f(s.end.x)}" y2="${f(s.end.y)}" '
              '$stroke stroke-linecap="round"/>',
            );
            if (s.kind == ShapeKind.arrow) {
              final (a, b) = arrowHead(s.start, s.end, s.strokeWidth);
              out.writeln(
                '<polyline points="${f(a.x)},${f(a.y)} ${f(s.end.x)},${f(s.end.y)} ${f(b.x)},${f(b.y)}" '
                'fill="none" $stroke stroke-linecap="round" stroke-linejoin="round"/>',
              );
            }
        }
      case TextObject t:
        final lh = t.fontSize * BoardStyle.lineHeight;
        out.write('<text $font font-size="${f(t.fontSize)}" ${paint('fill', t.color)}>');
        final lines = t.text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final y = t.position.y + lh * i + t.fontSize;
          out.write('<tspan x="${f(t.position.x)}" y="${f(y)}">${_escape(lines[i])}</tspan>');
        }
        out.writeln('</text>');
      case StickyNote n:
        const pad = BoardStyle.stickyPadding;
        const fs = BoardStyle.stickyFontSize;
        out.writeln(
          '<rect x="${f(n.position.x)}" y="${f(n.position.y)}" width="${f(n.size.x)}" height="${f(n.size.y)}" '
          'rx="2" ${paint('fill', n.color)}/>',
        );
        final lines = _wrap(n.text, maxChars: math.max(4, ((n.size.x - pad * 2) / (fs * 0.55)).floor()));
        if (lines.isNotEmpty) {
          out.write('<text $font font-size="${f(fs)}" fill="#17181a">');
          for (var i = 0; i < lines.length; i++) {
            final y = n.position.y + pad + fs + i * fs * BoardStyle.lineHeight;
            if (y > n.position.y + n.size.y - pad / 2) break;
            out.write('<tspan x="${f(n.position.x + pad)}" y="${f(y)}">${_escape(lines[i])}</tspan>');
          }
          out.writeln('</text>');
        }
      case ComponentObject c:
        _component(out, c, paint, f);
    }
  }
  out.writeln('</svg>');
  return out.toString();
}

void _component(StringBuffer out, ComponentObject c, String Function(String, int) paint, String Function(double) f) {
  final b = c.bounds;
  final layout = ComponentLayout.of(c);
  const font = 'font-family="${BoardStyle.fontFamily}, system-ui, sans-serif"';
  const fs = ComponentStyle.labelFontSize;
  final rect = 'x="${f(b.left)}" y="${f(b.top)}" width="${f(b.width)}" height="${f(b.height)}"';
  final width = 'stroke-width="${f(ComponentStyle.borderWidth)}"';
  if (c.isZone) {
    out.writeln(
      '<rect $rect rx="${f(ComponentStyle.zoneRadius)}" ${paint('fill', ComponentStyle.zoneFill(c.color))} '
      '${paint('stroke', c.color)} $width '
      'stroke-dasharray="${f(ComponentStyle.zoneDash)} ${f(ComponentStyle.zoneGap)}"/>',
    );
  } else {
    out.writeln(
      '<rect $rect rx="${f(ComponentStyle.cardRadius)}" ${paint('fill', ComponentStyle.cardFill)} '
      '${paint('stroke', ComponentStyle.border(c.color))} $width/>',
    );
  }
  out.writeln(componentIconSvg(c.icon, layout.icon, c.color));
  if (c.label.isEmpty) return;
  final l = layout.label;
  if (c.isZone) {
    final chars = math.max(1, (l.width / (fs * 0.55)).floor());
    final text = c.label.length > chars ? '${c.label.substring(0, math.max(0, chars - 1))}…' : c.label;
    out.writeln(
      '<text $font font-size="${f(fs)}" font-weight="600" ${paint('fill', c.color)} '
      'x="${f(l.left)}" y="${f(l.center.y + fs * 0.35)}">${_escape(text)}</text>',
    );
    return;
  }
  final lh = fs * BoardStyle.lineHeight;
  var lines = _wrap(c.label, maxChars: math.max(4, (l.width / (fs * 0.55)).floor()));
  if (lines.length > ComponentStyle.labelLines) {
    lines = [...lines.take(ComponentStyle.labelLines - 1), '${lines[ComponentStyle.labelLines - 1]}…'];
  }
  final top = l.center.y - lines.length * lh / 2;
  out.write('<text $font font-size="${f(fs)}" font-weight="500" ${paint('fill', ComponentStyle.labelColor)} text-anchor="middle">');
  for (var i = 0; i < lines.length; i++) {
    out.write('<tspan x="${f(l.center.x)}" y="${f(top + lh * i + fs)}">${_escape(lines[i])}</tspan>');
  }
  out.writeln('</text>');
}

/// A component icon as an SVG group scaled from its 24×24 grid into [box].
String componentIconSvg(ComponentIcon icon, Bounds box, int color) {
  String f(double v) => v.toStringAsFixed(2);
  final rgb = '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final s = box.width / ComponentIcon.grid;
  final out = StringBuffer(
    '<g transform="translate(${f(box.left)} ${f(box.top)}) scale(${s.toStringAsFixed(4)})" fill="none" '
    'stroke="$rgb" stroke-width="${ComponentIcon.strokeWidth}" stroke-linecap="round" stroke-linejoin="round">',
  );
  for (final part in icon.parts) {
    final look = part.filled ? ' fill="$rgb" stroke="none"' : '';
    out.write(switch (part) {
      IconLine l => '<line x1="${f(l.x1)}" y1="${f(l.y1)}" x2="${f(l.x2)}" y2="${f(l.y2)}"$look/>',
      IconRect r => '<rect x="${f(r.x)}" y="${f(r.y)}" width="${f(r.width)}" height="${f(r.height)}" rx="${f(r.radius)}"$look/>',
      IconCircle c => '<circle cx="${f(c.cx)}" cy="${f(c.cy)}" r="${f(c.r)}"$look/>',
      IconEllipse e => '<ellipse cx="${f(e.cx)}" cy="${f(e.cy)}" rx="${f(e.rx)}" ry="${f(e.ry)}"$look/>',
      IconPolyline p =>
        '<${p.closed ? 'polygon' : 'polyline'} points="${[for (var i = 0; i + 1 < p.points.length; i += 2) '${f(p.points[i])},${f(p.points[i + 1])}'].join(' ')}"$look/>',
      IconPath p => '<path d="${p.data}"$look/>',
    });
  }
  out.write('</g>');
  return out.toString();
}

List<String> _wrap(String text, {required int maxChars}) {
  final out = <String>[];
  for (final para in text.split('\n')) {
    var line = '';
    for (final word in para.split(' ')) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= maxChars) {
        line = '$line $word';
      } else {
        out.add(line);
        line = word;
      }
    }
    out.add(line);
  }
  return out;
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
