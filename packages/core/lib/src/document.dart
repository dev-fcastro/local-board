import 'geometry.dart';
import 'ids.dart';
import 'migrations.dart';
import 'objects.dart';

/// Where the camera was when the board was last saved.
/// screen = world * zoom + pan
final class Camera {
  const Camera({this.pan = Vec2.zero, this.zoom = 1});

  static const minZoom = 0.1;
  static const maxZoom = 8.0;

  final Vec2 pan;
  final double zoom;

  Vec2 toWorld(Vec2 screen) => Vec2((screen.x - pan.x) / zoom, (screen.y - pan.y) / zoom);
  Vec2 toScreen(Vec2 world) => Vec2(world.x * zoom + pan.x, world.y * zoom + pan.y);

  /// Zooms by [factor] keeping the world point under [focal] (screen) fixed.
  Camera zoomAt(Vec2 focal, double factor) {
    final z = (zoom * factor).clamp(minZoom, maxZoom);
    final world = toWorld(focal);
    return Camera(zoom: z, pan: Vec2(focal.x - world.x * z, focal.y - world.y * z));
  }

  Camera panBy(Vec2 delta) => Camera(pan: pan + delta, zoom: zoom);

  /// Frames [content] inside a [screen]-sized view with [margin] px around it.
  static Camera fit(Bounds content, Vec2 screen, {double margin = 48, double maxZoomLevel = 1}) {
    final w = content.width <= 0 ? 1.0 : content.width;
    final h = content.height <= 0 ? 1.0 : content.height;
    final availW = (screen.x - margin * 2).clamp(1.0, double.infinity);
    final availH = (screen.y - margin * 2).clamp(1.0, double.infinity);
    var z = availW / w < availH / h ? availW / w : availH / h;
    z = z.clamp(minZoom, maxZoomLevel);
    final c = content.center;
    return Camera(zoom: z, pan: Vec2(screen.x / 2 - c.x * z, screen.y / 2 - c.y * z));
  }

  Map<String, Object?> toJson() => {'pan': pan.toJson(), 'zoom': zoom};

  factory Camera.fromJson(Object? json) {
    if (json is! Map) return const Camera();
    final zoom = json['zoom'];
    return Camera(
      pan: json['pan'] == null ? Vec2.zero : Vec2.fromJson(json['pan']),
      zoom: zoom is num ? zoom.toDouble().clamp(minZoom, maxZoom) : 1,
    );
  }

  @override
  bool operator ==(Object other) => other is Camera && other.pan == pan && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(pan, zoom);
}

/// A board: metadata + objects in z-order (first = bottom).
///
/// Mutation happens only through the low-level operations below, which are
/// what commands use. The UI never edits objects directly (plan §8).
final class BoardDocument {
  BoardDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.viewport = const Camera(),
    Iterable<BoardObject> objects = const [],
  }) {
    for (final o in objects) {
      if (_byId.containsKey(o.id)) throw FormatException('Duplicate object id: ${o.id}');
      _byId[o.id] = o;
      _order.add(o.id);
    }
  }

  factory BoardDocument.create({String title = 'Untitled board', DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    return BoardDocument(id: newId(), title: title, createdAt: t, updatedAt: t);
  }

  /// File format marker so we never try to parse a random JSON as a board.
  static const formatName = 'local-board';

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  Camera viewport;

  final Map<String, BoardObject> _byId = {};
  final List<String> _order = [];

  /// Bumped on every content change. Cheap change detection for UI/autosave.
  int get revision => _revision;
  int _revision = 0;

  /// Changes whenever anything worth saving changes, including the camera.
  /// Both counters only grow, so the sum is a valid change marker.
  int get saveRevision => _revision + _viewRevision;
  int _viewRevision = 0;

  /// Camera moves are saved (to reopen exactly where you left off) but are
  /// not edits: they neither enter undo history nor change [updatedAt].
  void setViewport(Camera v) {
    if (v == viewport) return;
    viewport = v;
    _viewRevision++;
  }

  int get length => _order.length;
  bool get isEmpty => _order.isEmpty;

  Iterable<BoardObject> get objects => _order.map((id) => _byId[id]!);

  BoardObject? operator [](String id) => _byId[id];
  bool contains(String id) => _byId.containsKey(id);
  int indexOf(String id) => _order.indexOf(id);
  List<String> get order => List.unmodifiable(_order);

  Bounds? get contentBounds => Bounds.union(objects.map((o) => o.bounds));

  /// Topmost object under [p], or null.
  BoardObject? hitTest(Vec2 p, double tolerance) {
    for (var i = _order.length - 1; i >= 0; i--) {
      final o = _byId[_order[i]]!;
      if (o.hitTest(p, tolerance)) return o;
    }
    return null;
  }

  /// Objects whose bounds are fully inside [area] (marquee selection).
  List<BoardObject> objectsInside(Bounds area) => [
    for (final o in objects)
      if (area.containsBounds(o.bounds)) o,
  ];

  // ---- low-level operations (used by commands) ----

  void insertAt(int index, BoardObject object) {
    if (_byId.containsKey(object.id)) throw StateError('Object ${object.id} already exists');
    _byId[object.id] = object;
    _order.insert(index.clamp(0, _order.length), object.id);
    _touch();
  }

  /// Removes and returns the object with its previous index.
  (int, BoardObject) removeById(String id) {
    final o = _byId.remove(id);
    if (o == null) throw StateError('Object $id does not exist');
    final i = _order.indexOf(id);
    _order.removeAt(i);
    _touch();
    return (i, o);
  }

  void replace(BoardObject object) {
    if (!_byId.containsKey(object.id)) throw StateError('Object ${object.id} does not exist');
    _byId[object.id] = object;
    _touch();
  }

  void setOrder(List<String> order) {
    if (order.length != _order.length || !order.every(_byId.containsKey)) {
      throw StateError('Order must be a permutation of the current objects');
    }
    _order
      ..clear()
      ..addAll(order);
    _touch();
  }

  void rename(String newTitle) {
    title = newTitle;
    _touch();
  }

  void _touch() {
    _revision++;
    updatedAt = DateTime.now().toUtc();
  }

  // ---- serialization ----

  Map<String, Object?> toJson() => {
    'format': formatName,
    'schemaVersion': currentSchemaVersion,
    'boardId': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'viewport': viewport.toJson(),
    'objects': [for (final o in objects) o.toJson()],
  };

  /// Parses any supported schema version, migrating old files forward.
  factory BoardDocument.fromJson(Map<String, Object?> raw) {
    final json = migrateToCurrent(raw);
    final objects = json['objects'];
    if (objects is! List) throw const FormatException('Board has no object list');
    final doc = BoardDocument(
      id: json['boardId'] is String ? json['boardId'] as String : throw const FormatException('Missing boardId'),
      title: json['title'] is String ? json['title'] as String : 'Untitled board',
      createdAt: DateTime.tryParse('${json['createdAt']}')?.toUtc() ?? DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse('${json['updatedAt']}')?.toUtc() ?? DateTime.now().toUtc(),
      viewport: Camera.fromJson(json['viewport']),
      objects: [for (final o in objects) BoardObject.fromJson((o as Map).cast<String, Object?>())],
    );
    return doc;
  }
}
