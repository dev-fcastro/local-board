import 'dart:math' as math;

import 'geometry.dart';
import 'plugins/plugin.dart';
import 'plugins/registry.dart';

/// Colors are 32-bit ARGB ints in memory and `#rrggbbaa` strings on disk,
/// so files stay readable and portable outside of Flutter.
String colorToJson(int argb) {
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final a = ((argb >> 24) & 0xFF).toRadixString(16).padLeft(2, '0');
  return '#$rgb$a';
}

int colorFromJson(Object? json) {
  if (json is String && json.startsWith('#') && (json.length == 7 || json.length == 9)) {
    final rgb = int.parse(json.substring(1, 7), radix: 16);
    final a = json.length == 9 ? int.parse(json.substring(7, 9), radix: 16) : 0xFF;
    return (a << 24) | rgb;
  }
  throw FormatException('Invalid color: $json');
}

/// Anything that lives on a board. Immutable: every edit yields a new value
/// with the same [id].
sealed class BoardObject {
  const BoardObject();

  String get id;
  String get type;

  /// World-space bounds including stroke thickness.
  Bounds get bounds;

  BoardObject translate(Vec2 delta);

  /// Maps this object from the [from] frame into the [to] frame (resize).
  BoardObject resize(Bounds from, Bounds to);

  /// Whether world point [p] touches this object, within [tolerance] world units.
  bool hitTest(Vec2 p, double tolerance);

  /// Same content under a new identity (duplicate / paste).
  BoardObject withId(String id);

  Map<String, Object?> toJson();

  static BoardObject fromJson(Map<String, Object?> json) {
    final type = json['type'];
    return switch (type) {
      StrokeObject.typeName => StrokeObject.fromJson(json),
      ShapeObject.typeName => ShapeObject.fromJson(json),
      TextObject.typeName => TextObject.fromJson(json),
      StickyNote.typeName => StickyNote.fromJson(json),
      ComponentObject.typeName => ComponentObject.fromJson(json),
      _ => throw FormatException('Unknown object type: $type'),
    };
  }
}

String _id(Map<String, Object?> json) {
  final id = json['id'];
  if (id is String && id.isNotEmpty) return id;
  throw FormatException('Object without id: $json');
}

/// Maps [p] from frame [from] to frame [to] (degenerate axes keep offsets).
Vec2 mapPoint(Vec2 p, Bounds from, Bounds to) {
  final sx = from.width == 0 ? 1.0 : to.width / from.width;
  final sy = from.height == 0 ? 1.0 : to.height / from.height;
  return Vec2(to.left + (p.x - from.left) * sx, to.top + (p.y - from.top) * sy);
}

double _num(Map<String, Object?> json, String key, double fallback) {
  final v = json[key];
  return v is num ? v.toDouble() : fallback;
}

/// Freehand pen stroke.
final class StrokeObject extends BoardObject {
  StrokeObject({required this.id, required List<Vec2> points, required this.color, required this.width})
    : points = List.unmodifiable(points);

  static const typeName = 'stroke';

  @override
  final String id;
  final List<Vec2> points;
  final int color;
  final double width;

  @override
  String get type => typeName;

  @override
  late final Bounds bounds = Bounds.enclosing(points).inflate(width / 2);

  @override
  StrokeObject translate(Vec2 d) =>
      StrokeObject(id: id, points: [for (final p in points) p + d], color: color, width: width);

  @override
  bool hitTest(Vec2 p, double tolerance) {
    final reach = tolerance + width / 2;
    if (!bounds.inflate(tolerance).contains(p)) return false;
    if (points.length == 1) return p.distanceTo(points.first) <= reach;
    for (var i = 1; i < points.length; i++) {
      if (distanceToSegment(p, points[i - 1], points[i]) <= reach) return true;
    }
    return false;
  }

  @override
  StrokeObject resize(Bounds from, Bounds to) =>
      StrokeObject(id: id, points: [for (final p in points) mapPoint(p, from, to)], color: color, width: width);

  @override
  StrokeObject withId(String id) => StrokeObject(id: id, points: points, color: color, width: width);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'color': colorToJson(color),
    'width': width,
    'points': [for (final p in points) ...p.toJson()],
  };

  factory StrokeObject.fromJson(Map<String, Object?> json) {
    final flat = json['points'];
    if (flat is! List || flat.length.isOdd || flat.isEmpty) {
      throw FormatException('Invalid stroke points: ${json['id']}');
    }
    return StrokeObject(
      id: _id(json),
      color: colorFromJson(json['color']),
      width: _num(json, 'width', 2),
      points: [
        for (var i = 0; i < flat.length; i += 2) Vec2((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()),
      ],
    );
  }
}

enum ShapeKind { rectangle, ellipse, line, arrow }

/// Rectangle, ellipse, line or arrow spanned by [start]→[end].
final class ShapeObject extends BoardObject {
  const ShapeObject({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.strokeColor,
    required this.strokeWidth,
    this.fillColor,
  });

  static const typeName = 'shape';

  @override
  final String id;
  final ShapeKind kind;
  final Vec2 start;
  final Vec2 end;
  final int strokeColor;
  final double strokeWidth;
  final int? fillColor;

  bool get isLinear => kind == ShapeKind.line || kind == ShapeKind.arrow;

  @override
  String get type => typeName;

  @override
  Bounds get bounds {
    // Arrow heads stick out past the segment.
    final pad = strokeWidth / 2 + (kind == ShapeKind.arrow ? arrowHeadLength(strokeWidth) : 0);
    return Bounds.fromPoints(start, end).inflate(pad);
  }

  static double arrowHeadLength(double strokeWidth) => math.max(12, strokeWidth * 4);

  @override
  ShapeObject translate(Vec2 d) => copyWith(start: start + d, end: end + d);

  @override
  ShapeObject resize(Bounds from, Bounds to) => copyWith(start: mapPoint(start, from, to), end: mapPoint(end, from, to));

  @override
  bool hitTest(Vec2 p, double tolerance) {
    final reach = tolerance + strokeWidth / 2;
    final box = Bounds.fromPoints(start, end);
    switch (kind) {
      case ShapeKind.line:
      case ShapeKind.arrow:
        return distanceToSegment(p, start, end) <= reach;
      case ShapeKind.rectangle:
        if (fillColor != null && box.contains(p)) return true;
        if (!box.inflate(reach).contains(p)) return false;
        final inner = box.inflate(-reach);
        return inner.width <= 0 || inner.height <= 0 || !inner.contains(p);
      case ShapeKind.ellipse:
        final rx = box.width / 2, ry = box.height / 2;
        if (rx < 0.5 || ry < 0.5) return distanceToSegment(p, start, end) <= reach;
        final c = box.center;
        final dx = p.x - c.x, dy = p.y - c.y;
        final n = math.sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry));
        if (fillColor != null && n <= 1) return true;
        // Radial distance approximation, good enough for hit slop.
        return (n - 1).abs() * math.min(rx, ry) <= reach;
    }
  }

  ShapeObject copyWith({
    String? id,
    Vec2? start,
    Vec2? end,
    int? strokeColor,
    double? strokeWidth,
    int? Function()? fillColor,
  }) => ShapeObject(
    id: id ?? this.id,
    kind: kind,
    start: start ?? this.start,
    end: end ?? this.end,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    fillColor: fillColor != null ? fillColor() : this.fillColor,
  );

  @override
  ShapeObject withId(String id) => copyWith(id: id);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'kind': kind.name,
    'start': start.toJson(),
    'end': end.toJson(),
    'strokeColor': colorToJson(strokeColor),
    'strokeWidth': strokeWidth,
    if (fillColor != null) 'fillColor': colorToJson(fillColor!),
  };

  factory ShapeObject.fromJson(Map<String, Object?> json) {
    final kind = ShapeKind.values.asNameMap()[json['kind']];
    if (kind == null) throw FormatException('Unknown shape kind: ${json['kind']}');
    return ShapeObject(
      id: _id(json),
      kind: kind,
      start: Vec2.fromJson(json['start']),
      end: Vec2.fromJson(json['end']),
      strokeColor: colorFromJson(json['strokeColor']),
      strokeWidth: _num(json, 'strokeWidth', 2),
      fillColor: json['fillColor'] == null ? null : colorFromJson(json['fillColor']),
    );
  }
}

/// Free text. [size] is measured by the renderer when the text is committed
/// and stored so the domain can hit-test without a text engine.
final class TextObject extends BoardObject {
  const TextObject({
    required this.id,
    required this.position,
    required this.text,
    required this.fontSize,
    required this.color,
    required this.size,
  });

  static const typeName = 'text';

  @override
  final String id;
  final Vec2 position;
  final String text;
  final double fontSize;
  final int color;
  final Vec2 size;

  @override
  String get type => typeName;

  @override
  Bounds get bounds => Bounds(position.x, position.y, position.x + size.x, position.y + size.y);

  @override
  TextObject translate(Vec2 d) => copyWith(position: position + d);

  /// Text scales uniformly (by height) so glyphs never get distorted.
  @override
  TextObject resize(Bounds from, Bounds to) {
    final s = from.height == 0 ? 1.0 : (to.height / from.height).abs();
    return copyWith(
      position: mapPoint(position, from, to),
      fontSize: math.max(4, fontSize * s),
      size: Vec2(size.x * s, size.y * s),
    );
  }

  @override
  bool hitTest(Vec2 p, double tolerance) => bounds.inflate(tolerance).contains(p);

  TextObject copyWith({String? id, Vec2? position, String? text, double? fontSize, int? color, Vec2? size}) =>
      TextObject(
        id: id ?? this.id,
        position: position ?? this.position,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        size: size ?? this.size,
      );

  @override
  TextObject withId(String id) => copyWith(id: id);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'position': position.toJson(),
    'size': size.toJson(),
    'text': text,
    'fontSize': fontSize,
    'color': colorToJson(color),
  };

  factory TextObject.fromJson(Map<String, Object?> json) => TextObject(
    id: _id(json),
    position: Vec2.fromJson(json['position']),
    size: Vec2.fromJson(json['size']),
    text: json['text'] is String ? json['text'] as String : '',
    fontSize: _num(json, 'fontSize', 24),
    color: colorFromJson(json['color']),
  );
}

/// A sticky note: a colored square with wrapped text.
final class StickyNote extends BoardObject {
  const StickyNote({
    required this.id,
    required this.position,
    required this.size,
    required this.text,
    required this.color,
  });

  static const typeName = 'sticky';
  static const defaultSize = Vec2(200, 200);

  @override
  final String id;
  final Vec2 position;
  final Vec2 size;
  final String text;
  final int color;

  @override
  String get type => typeName;

  @override
  Bounds get bounds => Bounds(position.x, position.y, position.x + size.x, position.y + size.y);

  @override
  StickyNote translate(Vec2 d) => copyWith(position: position + d);

  @override
  StickyNote resize(Bounds from, Bounds to) {
    final a = mapPoint(position, from, to);
    final b = mapPoint(position + size, from, to);
    final box = Bounds.fromPoints(a, b);
    return copyWith(position: box.topLeft, size: Vec2(math.max(40, box.width), math.max(40, box.height)));
  }

  @override
  bool hitTest(Vec2 p, double tolerance) => bounds.inflate(tolerance).contains(p);

  StickyNote copyWith({String? id, Vec2? position, Vec2? size, String? text, int? color}) => StickyNote(
    id: id ?? this.id,
    position: position ?? this.position,
    size: size ?? this.size,
    text: text ?? this.text,
    color: color ?? this.color,
  );

  @override
  StickyNote withId(String id) => copyWith(id: id);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'position': position.toJson(),
    'size': size.toJson(),
    'text': text,
    'color': colorToJson(color),
  };

  factory StickyNote.fromJson(Map<String, Object?> json) => StickyNote(
    id: _id(json),
    position: Vec2.fromJson(json['position']),
    size: json['size'] == null ? defaultSize : Vec2.fromJson(json['size']),
    text: json['text'] is String ? json['text'] as String : '',
    color: colorFromJson(json['color']),
  );
}

/// A component from a plugin (a service, a router, a subnet…). The board only
/// stores which plugin and kind it is; the icon comes from the plugin, so a
/// board stays small and a missing plugin never loses data.
final class ComponentObject extends BoardObject {
  const ComponentObject({
    required this.id,
    required this.plugin,
    required this.kind,
    required this.position,
    required this.size,
    required this.label,
    required this.color,
  });

  static const typeName = 'component';

  /// Height of a zone's label strip, which is also where it can be grabbed.
  static const zoneHeader = 36.0;

  @override
  final String id;
  final String plugin;
  final String kind;
  final Vec2 position;
  final Vec2 size;
  final String label;
  final int color;

  /// The plugin's definition, or null when this build does not know it.
  ComponentKind? get definition => findComponentKind(plugin, kind);

  /// Falls back to a placeholder so boards from newer plugins still render.
  ComponentIcon get icon => definition?.icon ?? unknownComponentIcon;

  ComponentBody get body => definition?.body ?? ComponentBody.card;
  bool get isZone => body == ComponentBody.zone;

  double get minSize => isZone ? 80 : 40;

  @override
  String get type => typeName;

  @override
  Bounds get bounds => Bounds(position.x, position.y, position.x + size.x, position.y + size.y);

  @override
  ComponentObject translate(Vec2 d) => copyWith(position: position + d);

  @override
  ComponentObject resize(Bounds from, Bounds to) {
    final box = Bounds.fromPoints(mapPoint(position, from, to), mapPoint(position + size, from, to));
    return copyWith(position: box.topLeft, size: Vec2(math.max(minSize, box.width), math.max(minSize, box.height)));
  }

  /// Cards are solid. Zones only react on their border and label strip, so
  /// clicking inside one still selects what it contains or starts a marquee.
  @override
  bool hitTest(Vec2 p, double tolerance) {
    final b = bounds;
    if (!b.inflate(tolerance).contains(p)) return false;
    if (!isZone) return true;
    if (p.y <= b.top + zoneHeader) return true;
    final edge = tolerance + 6;
    return p.x - b.left <= edge || b.right - p.x <= edge || b.bottom - p.y <= edge;
  }

  ComponentObject copyWith({String? id, Vec2? position, Vec2? size, String? label, int? color}) => ComponentObject(
    id: id ?? this.id,
    plugin: plugin,
    kind: kind,
    position: position ?? this.position,
    size: size ?? this.size,
    label: label ?? this.label,
    color: color ?? this.color,
  );

  @override
  ComponentObject withId(String id) => copyWith(id: id);

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'plugin': plugin,
    'kind': kind,
    'position': position.toJson(),
    'size': size.toJson(),
    'label': label,
    'color': colorToJson(color),
  };

  factory ComponentObject.fromJson(Map<String, Object?> json) {
    final plugin = json['plugin'], kind = json['kind'];
    if (plugin is! String || plugin.isEmpty || kind is! String || kind.isEmpty) {
      throw FormatException('Component without plugin/kind: ${json['id']}');
    }
    return ComponentObject(
      id: _id(json),
      plugin: plugin,
      kind: kind,
      position: Vec2.fromJson(json['position']),
      size: Vec2.fromJson(json['size']),
      label: json['label'] is String ? json['label'] as String : '',
      color: colorFromJson(json['color']),
    );
  }
}
