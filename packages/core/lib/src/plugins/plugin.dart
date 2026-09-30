import '../geometry.dart';

/// One drawing instruction of a component icon, on a 24×24 grid.
/// Icons are data (not code) so the canvas, PNG and SVG export all draw the
/// exact same thing, and plugins can later ship as plain files.
sealed class IconPart {
  const IconPart({this.filled = false});

  /// Filled instead of stroked.
  final bool filled;
}

final class IconLine extends IconPart {
  const IconLine(this.x1, this.y1, this.x2, this.y2);

  final double x1, y1, x2, y2;
}

final class IconRect extends IconPart {
  const IconRect(this.x, this.y, this.width, this.height, {this.radius = 0, super.filled});

  final double x, y, width, height, radius;
}

final class IconCircle extends IconPart {
  const IconCircle(this.cx, this.cy, this.r, {super.filled});

  final double cx, cy, r;
}

final class IconEllipse extends IconPart {
  const IconEllipse(this.cx, this.cy, this.rx, this.ry, {super.filled});

  final double cx, cy, rx, ry;
}

/// Connected points `[x0, y0, x1, y1, …]`, optionally closed.
final class IconPolyline extends IconPart {
  const IconPolyline(this.points, {this.closed = false, super.filled});

  final List<double> points;
  final bool closed;
}

/// Free path using absolute `M L H V C Z` commands only (see [parseIconPath]).
final class IconPath extends IconPart {
  const IconPath(this.data, {super.filled});

  final String data;
}

final class ComponentIcon {
  const ComponentIcon(this.parts);

  static const grid = 24.0;
  static const strokeWidth = 1.5;

  final List<IconPart> parts;
}

/// How a component is drawn on the board.
enum ComponentBody {
  /// Icon above a label inside a card (a service, a router…).
  card,

  /// Dashed container with its label in the corner (a boundary, a subnet…).
  zone,
}

/// A type of component a plugin offers (e.g. "Database").
final class ComponentKind {
  const ComponentKind({
    required this.id,
    required this.label,
    required this.icon,
    this.body = ComponentBody.card,
    Vec2? defaultSize,
  }) : _defaultSize = defaultSize;

  final String id;
  final String label;
  final ComponentIcon icon;
  final ComponentBody body;
  final Vec2? _defaultSize;

  Vec2 get defaultSize => _defaultSize ?? (body == ComponentBody.zone ? const Vec2(420, 280) : const Vec2(150, 120));
}

/// A named set of components, e.g. "Network architecture".
final class BoardPlugin {
  const BoardPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.color,
    required this.kinds,
  });

  /// Stable id written into boards. Never change it once released.
  final String id;
  final String name;
  final String description;
  final String version;

  /// Default ARGB color of its components.
  final int color;
  final List<ComponentKind> kinds;

  ComponentKind? kind(String id) {
    for (final k in kinds) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// A segment of a parsed [IconPath].
sealed class PathSegment {
  const PathSegment();
}

final class MoveTo extends PathSegment {
  const MoveTo(this.x, this.y);
  final double x, y;
}

final class LineTo extends PathSegment {
  const LineTo(this.x, this.y);
  final double x, y;
}

final class CubicTo extends PathSegment {
  const CubicTo(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
  final double x1, y1, x2, y2, x, y;
}

final class ClosePath extends PathSegment {
  const ClosePath();
}

/// Parses the small SVG path subset icons may use: absolute `M L H V C Z`.
List<PathSegment> parseIconPath(String data) {
  final tokens = RegExp(r'[MLHVCZ]|-?\d*\.?\d+').allMatches(data).map((m) => m.group(0)!).toList();
  final out = <PathSegment>[];
  var i = 0;
  var cx = 0.0, cy = 0.0;
  String? command;

  double next() {
    if (i >= tokens.length) throw FormatException('Truncated icon path: $data');
    final v = double.tryParse(tokens[i++]);
    if (v == null) throw FormatException('Expected a number in icon path: $data');
    return v;
  }

  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[MLHVCZ]$').hasMatch(t)) {
      command = t;
      i++;
      if (t == 'Z') {
        out.add(const ClosePath());
        continue;
      }
    } else if (command == null || command == 'Z') {
      throw FormatException('Icon path must start with a command: $data');
    }
    switch (command) {
      case 'M':
        cx = next();
        cy = next();
        out.add(MoveTo(cx, cy));
        command = 'L'; // extra pairs after M are lines, as in SVG
      case 'L':
        cx = next();
        cy = next();
        out.add(LineTo(cx, cy));
      case 'H':
        cx = next();
        out.add(LineTo(cx, cy));
      case 'V':
        cy = next();
        out.add(LineTo(cx, cy));
      case 'C':
        final x1 = next(), y1 = next(), x2 = next(), y2 = next();
        cx = next();
        cy = next();
        out.add(CubicTo(x1, y1, x2, y2, cx, cy));
    }
  }
  return out;
}
