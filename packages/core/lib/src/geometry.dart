import 'dart:math' as math;

/// A 2D point or vector in world coordinates.
final class Vec2 {
  const Vec2(this.x, this.y);

  static const zero = Vec2(0, 0);

  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  Vec2 operator -() => Vec2(-x, -y);

  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Vec2 o) => (this - o).length;
  bool get isZero => x == 0 && y == 0;

  List<double> toJson() => [_round(x), _round(y)];

  static Vec2 fromJson(Object? json) {
    if (json is List && json.length == 2 && json[0] is num && json[1] is num) {
      return Vec2((json[0] as num).toDouble(), (json[1] as num).toDouble());
    }
    throw FormatException('Invalid point: $json');
  }

  @override
  bool operator ==(Object other) => other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2($x, $y)';
}

/// Keeps files small and diffs stable: 2 decimals is sub-pixel at any sane zoom.
double _round(double v) => (v * 100).roundToDouble() / 100;

/// Axis-aligned bounding box.
final class Bounds {
  const Bounds(this.left, this.top, this.right, this.bottom);

  factory Bounds.fromPoints(Vec2 a, Vec2 b) =>
      Bounds(math.min(a.x, b.x), math.min(a.y, b.y), math.max(a.x, b.x), math.max(a.y, b.y));

  factory Bounds.enclosing(Iterable<Vec2> points) {
    final it = points.iterator;
    if (!it.moveNext()) return const Bounds(0, 0, 0, 0);
    var l = it.current.x, t = it.current.y, r = l, b = t;
    while (it.moveNext()) {
      final p = it.current;
      if (p.x < l) l = p.x;
      if (p.x > r) r = p.x;
      if (p.y < t) t = p.y;
      if (p.y > b) b = p.y;
    }
    return Bounds(l, t, r, b);
  }

  static Bounds? union(Iterable<Bounds> all) {
    Bounds? acc;
    for (final b in all) {
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    return acc;
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  Vec2 get topLeft => Vec2(left, top);
  Vec2 get center => Vec2((left + right) / 2, (top + bottom) / 2);

  bool contains(Vec2 p) => p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  bool overlaps(Bounds o) => left <= o.right && right >= o.left && top <= o.bottom && bottom >= o.top;

  bool containsBounds(Bounds o) => o.left >= left && o.right <= right && o.top >= top && o.bottom <= bottom;

  Bounds inflate(double d) => Bounds(left - d, top - d, right + d, bottom + d);

  Bounds translate(Vec2 d) => Bounds(left + d.x, top + d.y, right + d.x, bottom + d.y);

  Bounds expandToInclude(Bounds o) => Bounds(
    math.min(left, o.left),
    math.min(top, o.top),
    math.max(right, o.right),
    math.max(bottom, o.bottom),
  );

  @override
  bool operator ==(Object other) =>
      other is Bounds && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Bounds($left, $top, $right, $bottom)';
}

/// Shortest distance from [p] to the segment [a]–[b].
double distanceToSegment(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final lenSq = ab.x * ab.x + ab.y * ab.y;
  if (lenSq == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lenSq).clamp(0.0, 1.0);
  return p.distanceTo(Vec2(a.x + ab.x * t, a.y + ab.y * t));
}

/// Snaps [end] so the segment from [start] sits on a multiple of 45°.
Vec2 snapAngle45(Vec2 start, Vec2 end) {
  final d = end - start;
  if (d.isZero) return end;
  const step = math.pi / 4;
  final angle = (math.atan2(d.y, d.x) / step).round() * step;
  final len = d.length;
  return Vec2(start.x + math.cos(angle) * len, start.y + math.sin(angle) * len);
}

/// Forces the box spanned by [start]→[end] to be square (keeps drag direction).
Vec2 snapSquare(Vec2 start, Vec2 end) {
  final d = end - start;
  final side = math.max(d.x.abs(), d.y.abs());
  return Vec2(start.x + side * (d.x < 0 ? -1 : 1), start.y + side * (d.y < 0 ? -1 : 1));
}
