import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton, kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:local_board_core/local_board_core.dart';

import 'palette.dart';
import 'text_layout.dart';
import 'tools.dart';

/// An open text or sticky-note editor. [objectId] is null while creating.
final class TextEditSession {
  const TextEditSession({
    required this.position,
    required this.initialText,
    required this.color,
    this.objectId,
    this.fontSize = 24,
    this.sticky = false,
    this.stickySize = StickyNote.defaultSize,
  });

  final String? objectId;
  final Vec2 position;
  final String initialText;
  final double fontSize;
  final int color;
  final bool sticky;
  final Vec2 stickySize;
}

enum _Gesture { none, pan, draw, shape, move, resize, marquee, erase }

enum Handle { topLeft, topRight, bottomLeft, bottomRight }

/// All board interaction lives here, independent of widgets so it can be
/// tested without pumping frames. Every document change goes through
/// [history]; the widget only forwards input and paints state.
class BoardController extends ChangeNotifier {
  BoardController(this.document) : history = History(document);

  static const clipboardFormat = 'local-board/objects';
  static const handleSize = 10.0; // screen px
  static const hitSlop = 6.0; // screen px

  final BoardDocument document;
  final History history;

  /// Size of the widget showing the board; set by the canvas widget.
  Size viewSize = Size.zero;

  // ---- tool state ----

  Tool get tool => _tool;
  Tool _tool = Tool.select;

  int get color => _color;
  int _color = Palette.ink;

  double get strokeWidth => _strokeWidth;
  double _strokeWidth = Palette.strokeWidths[1];

  double get textSize => _textSize;
  double _textSize = Palette.textSizes[1];

  int get stickyColor => _stickyColor;
  int _stickyColor = Palette.stickies.first;

  bool get spaceHeld => _spaceHeld;
  bool _spaceHeld = false;

  // ---- transient interaction state (read by the painter) ----

  final Set<String> selection = {};
  final Map<String, BoardObject> preview = {};
  final Set<String> erasing = {};
  BoardObject? draft;
  Bounds? marquee;
  TextEditSession? editing;

  _Gesture _gesture = _Gesture.none;
  Vec2 _downWorld = Vec2.zero;
  Offset _lastScreen = Offset.zero;
  Offset? hoverScreen;
  List<BoardObject> _originals = const [];
  Bounds? _resizeFrom;
  Vec2 _resizeAnchor = Vec2.zero;
  List<Vec2> _strokePoints = [];
  DateTime _lastDownAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastDownScreen = Offset.zero;
  Set<String> _marqueeBase = const {};

  bool get isPanning => _gesture == _Gesture.pan;
  bool get isInteracting => _gesture != _Gesture.none;

  Camera get camera => document.viewport;

  Vec2 toWorld(Offset screen) => camera.toWorld(Vec2(screen.dx, screen.dy));
  Offset toScreen(Vec2 world) {
    final s = camera.toScreen(world);
    return Offset(s.x, s.y);
  }

  List<BoardObject> get selectedObjects => [
    for (final o in document.objects)
      if (selection.contains(o.id)) o,
  ];

  Bounds? get selectionBounds => Bounds.union(selectedObjects.map((o) => preview[o.id]?.bounds ?? o.bounds));

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  void _emit() => notifyListeners();

  // ---- tools & styles ----

  void setTool(Tool t) {
    if (editing != null) return;
    _tool = t;
    if (t != Tool.select) selection.clear();
    _emit();
  }

  /// Sets the ink color and recolors selected non-sticky objects.
  void setColor(int c) {
    _color = c;
    _restyle((o) => switch (o) {
      StrokeObject s => StrokeObject(id: s.id, points: s.points, color: c, width: s.width),
      ShapeObject s => s.copyWith(strokeColor: c),
      TextObject t => t.copyWith(color: c),
      StickyNote() => null,
    }, 'Color');
  }

  void setStickyColor(int c) {
    _stickyColor = c;
    _restyle((o) => o is StickyNote ? o.copyWith(color: c) : null, 'Note color');
  }

  void setStrokeWidth(double w) {
    _strokeWidth = w;
    _restyle((o) => switch (o) {
      StrokeObject s => StrokeObject(id: s.id, points: s.points, color: s.color, width: w),
      ShapeObject s => s.copyWith(strokeWidth: w),
      _ => null,
    }, 'Stroke width');
  }

  void setTextSize(double size) {
    _textSize = size;
    _restyle(
      (o) => o is TextObject ? o.copyWith(fontSize: size, size: measureText(o.text, size)) : null,
      'Text size',
    );
  }

  void _restyle(BoardObject? Function(BoardObject) change, String label) {
    final before = <BoardObject>[], after = <BoardObject>[];
    for (final o in selectedObjects) {
      final n = change(o);
      if (n != null) {
        before.add(o);
        after.add(n);
      }
    }
    if (before.isNotEmpty) history.execute(UpdateObjects(before: before, after: after, label: label));
    _emit();
  }

  // ---- viewport ----

  void setCamera(Camera v) {
    document.setViewport(v);
    _emit();
  }

  void zoomBy(double factor, {Offset? focal}) {
    final f = focal ?? Offset(viewSize.width / 2, viewSize.height / 2);
    setCamera(camera.zoomAt(Vec2(f.dx, f.dy), factor));
  }

  void resetZoom() {
    final center = Offset(viewSize.width / 2, viewSize.height / 2);
    zoomBy(1 / camera.zoom, focal: center);
  }

  void zoomToFit() {
    final b = document.contentBounds;
    if (b == null || viewSize.isEmpty) {
      setCamera(Camera(pan: Vec2(viewSize.width / 2, viewSize.height / 2)));
      return;
    }
    setCamera(Camera.fit(b, Vec2(viewSize.width, viewSize.height), margin: 80));
  }

  void panBy(Offset delta) => setCamera(camera.panBy(Vec2(delta.dx, delta.dy)));

  // ---- pointer input ----

  void pointerDown(Offset screen, {int buttons = kPrimaryButton, bool shift = false}) {
    if (editing != null) return; // the editor commits on focus loss first
    final w = toWorld(screen);
    _downWorld = w;
    _lastScreen = screen;
    final now = DateTime.now();
    final isDouble =
        now.difference(_lastDownAt) < const Duration(milliseconds: 400) && (screen - _lastDownScreen).distance < 6;
    _lastDownAt = now;
    _lastDownScreen = screen;

    if (buttons & kMiddleMouseButton != 0 || _spaceHeld || _tool == Tool.hand) {
      _gesture = _Gesture.pan;
      _emit();
      return;
    }
    if (buttons & kPrimaryButton == 0) return;

    switch (_tool) {
      case Tool.select:
        final handle = handleAt(screen);
        if (handle != null) {
          _startResize(handle);
          break;
        }
        final hit = document.hitTest(w, hitSlop / camera.zoom);
        if (hit == null) {
          _gesture = _Gesture.marquee;
          _marqueeBase = shift ? {...selection} : const {};
          if (!shift) selection.clear();
          marquee = Bounds.fromPoints(w, w);
          break;
        }
        if (isDouble && (hit is TextObject || hit is StickyNote)) {
          beginEditObject(hit);
          return;
        }
        if (shift) {
          selection.contains(hit.id) ? selection.remove(hit.id) : selection.add(hit.id);
        } else if (!selection.contains(hit.id)) {
          selection
            ..clear()
            ..add(hit.id);
        }
        if (selection.contains(hit.id)) {
          _gesture = _Gesture.move;
          _originals = selectedObjects;
        }
      case Tool.hand:
        break;
      case Tool.pen:
        _gesture = _Gesture.draw;
        _strokePoints = [w];
        draft = StrokeObject(id: 'draft', points: _strokePoints, color: _color, width: _strokeWidth);
      case Tool.eraser:
        _gesture = _Gesture.erase;
        _eraseAt(w);
      case Tool.line:
      case Tool.arrow:
      case Tool.rectangle:
      case Tool.ellipse:
        _gesture = _Gesture.shape;
        draft = _shapeDraft(w, w);
      case Tool.text:
        final hit = document.hitTest(w, hitSlop / camera.zoom);
        if (hit is TextObject || hit is StickyNote) {
          beginEditObject(hit!);
        } else {
          editing = TextEditSession(
            position: Vec2(w.x, w.y - _textSize * BoardStyle.lineHeight / 2),
            initialText: '',
            fontSize: _textSize,
            color: _color,
          );
        }
      case Tool.sticky:
        editing = TextEditSession(
          position: w - StickyNote.defaultSize * 0.5,
          initialText: '',
          color: _stickyColor,
          sticky: true,
        );
    }
    _emit();
  }

  void pointerMove(Offset screen, {bool shift = false}) {
    hoverScreen = screen;
    final delta = screen - _lastScreen;
    _lastScreen = screen;
    final w = toWorld(screen);
    switch (_gesture) {
      case _Gesture.none:
        return;
      case _Gesture.pan:
        panBy(delta);
        return;
      case _Gesture.draw:
        final minDist = 1.5 / camera.zoom;
        if (w.distanceTo(_strokePoints.last) >= minDist) {
          _strokePoints.add(w);
          draft = StrokeObject(id: 'draft', points: _strokePoints, color: _color, width: _strokeWidth);
        }
      case _Gesture.shape:
        var end = w;
        if (shift) {
          end = (_tool == Tool.line || _tool == Tool.arrow) ? snapAngle45(_downWorld, w) : snapSquare(_downWorld, w);
        }
        draft = _shapeDraft(_downWorld, end);
      case _Gesture.move:
        var d = w - _downWorld;
        if (shift) d = d.x.abs() > d.y.abs() ? Vec2(d.x, 0) : Vec2(0, d.y);
        preview
          ..clear()
          ..addAll({for (final o in _originals) o.id: o.translate(d)});
      case _Gesture.resize:
        _resizeTo(w, keepAspect: shift || _originals.any((o) => o is TextObject));
      case _Gesture.marquee:
        marquee = Bounds.fromPoints(_downWorld, w);
        selection
          ..clear()
          ..addAll(_marqueeBase)
          ..addAll(document.objectsInside(marquee!).map((o) => o.id));
      case _Gesture.erase:
        _eraseAt(w);
    }
    _emit();
  }

  void pointerHover(Offset screen) {
    hoverScreen = screen;
  }

  void pointerUp() {
    switch (_gesture) {
      case _Gesture.none:
      case _Gesture.pan:
        break;
      case _Gesture.draw:
        if (_strokePoints.isNotEmpty) {
          history.execute(
            AddObjects([
              StrokeObject(id: newId(), points: _strokePoints, color: _color, width: _strokeWidth),
            ], label: 'Draw'),
          );
        }
      case _Gesture.shape:
        final d = draft;
        if (d is ShapeObject && d.start.distanceTo(d.end) * camera.zoom >= 4) {
          history.execute(AddObjects([d.withId(newId())], label: 'Add ${_tool.label.toLowerCase()}'));
        }
      case _Gesture.move:
      case _Gesture.resize:
        final after = [for (final o in _originals) preview[o.id] ?? o];
        final changed = [for (var i = 0; i < after.length; i++) !identical(after[i], _originals[i])].any((c) => c);
        if (changed && preview.isNotEmpty) {
          history.execute(
            UpdateObjects(
              before: _originals,
              after: after,
              label: _gesture == _Gesture.move ? 'Move' : 'Resize',
            ),
          );
        }
      case _Gesture.marquee:
        break;
      case _Gesture.erase:
        if (erasing.isNotEmpty) history.execute(DeleteObjects(erasing.toList(), label: 'Erase'));
    }
    _gesture = _Gesture.none;
    draft = null;
    marquee = null;
    preview.clear();
    erasing.clear();
    _originals = const [];
    _strokePoints = [];
    _emit();
  }

  void pointerCancel() {
    _gesture = _Gesture.none;
    draft = null;
    marquee = null;
    preview.clear();
    erasing.clear();
    _emit();
  }

  /// Wheel zooms around the cursor (plan §20).
  void scroll(Offset screen, Offset delta) {
    if (delta.dy == 0) return;
    zoomBy(math.pow(2, -delta.dy / 400).toDouble(), focal: screen);
  }

  void trackpad(Offset screen, Offset panDelta, double scaleDelta) {
    var v = camera.panBy(Vec2(panDelta.dx, panDelta.dy));
    if (scaleDelta != 1) v = v.zoomAt(Vec2(screen.dx, screen.dy), scaleDelta);
    setCamera(v);
  }

  ShapeObject _shapeDraft(Vec2 a, Vec2 b) => ShapeObject(
    id: 'draft',
    kind: switch (_tool) {
      Tool.line => ShapeKind.line,
      Tool.arrow => ShapeKind.arrow,
      Tool.ellipse => ShapeKind.ellipse,
      _ => ShapeKind.rectangle,
    },
    start: a,
    end: b,
    strokeColor: _color,
    strokeWidth: _strokeWidth,
  );

  void _eraseAt(Vec2 w) {
    final tol = (hitSlop + 4) / camera.zoom;
    for (final o in document.objects) {
      if (!erasing.contains(o.id) && o.hitTest(w, tol)) erasing.add(o.id);
    }
  }

  // ---- selection handles & resize ----

  Map<Handle, Offset> handlePositions() {
    final b = selectionBounds;
    if (b == null || _tool != Tool.select) return const {};
    final tl = toScreen(b.topLeft), br = toScreen(Vec2(b.right, b.bottom));
    const pad = 4.0;
    return {
      Handle.topLeft: Offset(tl.dx - pad, tl.dy - pad),
      Handle.topRight: Offset(br.dx + pad, tl.dy - pad),
      Handle.bottomLeft: Offset(tl.dx - pad, br.dy + pad),
      Handle.bottomRight: Offset(br.dx + pad, br.dy + pad),
    };
  }

  Handle? handleAt(Offset screen) {
    for (final e in handlePositions().entries) {
      if ((e.value - screen).distance <= handleSize) return e.key;
    }
    return null;
  }

  void _startResize(Handle h) {
    final b = selectionBounds!;
    _gesture = _Gesture.resize;
    _originals = selectedObjects;
    _resizeFrom = b;
    _resizeAnchor = switch (h) {
      Handle.topLeft => Vec2(b.right, b.bottom),
      Handle.topRight => Vec2(b.left, b.bottom),
      Handle.bottomLeft => Vec2(b.right, b.top),
      Handle.bottomRight => Vec2(b.left, b.top),
    };
  }

  void _resizeTo(Vec2 w, {required bool keepAspect}) {
    final from = _resizeFrom!;
    final min = 8 / camera.zoom;
    var dx = w.x - _resizeAnchor.x, dy = w.y - _resizeAnchor.y;
    // Moving handle side stays on its side: no flipping in v0.1.
    final sx = (_resizeAnchor.x == from.left) ? 1 : -1;
    final sy = (_resizeAnchor.y == from.top) ? 1 : -1;
    var width = math.max(min, dx * sx);
    var height = math.max(min, dy * sy);
    if (keepAspect && from.width > 0 && from.height > 0) {
      final s = math.max(width / from.width, height / from.height);
      width = from.width * s;
      height = from.height * s;
    }
    final to = Bounds.fromPoints(_resizeAnchor, Vec2(_resizeAnchor.x + width * sx, _resizeAnchor.y + height * sy));
    preview
      ..clear()
      ..addAll({for (final o in _originals) o.id: o.resize(from, to)});
  }

  // ---- text editing ----

  void beginEditObject(BoardObject o) {
    selection
      ..clear()
      ..add(o.id);
    editing = switch (o) {
      TextObject t => TextEditSession(
        objectId: t.id,
        position: t.position,
        initialText: t.text,
        fontSize: t.fontSize,
        color: t.color,
      ),
      StickyNote n => TextEditSession(
        objectId: n.id,
        position: n.position,
        initialText: n.text,
        color: n.color,
        sticky: true,
        stickySize: n.size,
      ),
      _ => null,
    };
    _emit();
  }

  void commitEdit(String text) {
    final s = editing;
    if (s == null) return;
    editing = null;
    final existing = s.objectId == null ? null : document[s.objectId!];
    final blank = text.trim().isEmpty;

    if (s.sticky) {
      if (existing is StickyNote) {
        if (existing.text != text) {
          history.execute(UpdateObjects(before: [existing], after: [existing.copyWith(text: text)], label: 'Edit note'));
        }
      } else {
        final note = StickyNote(id: newId(), position: s.position, size: s.stickySize, text: text, color: s.color);
        history.execute(AddObjects([note], label: 'Add note'));
        selection
          ..clear()
          ..add(note.id);
      }
    } else if (existing is TextObject) {
      if (blank) {
        history.execute(DeleteObjects([existing.id], label: 'Delete text'));
        selection.remove(existing.id);
      } else if (existing.text != text) {
        history.execute(
          UpdateObjects(
            before: [existing],
            after: [existing.copyWith(text: text, size: measureText(text, existing.fontSize))],
            label: 'Edit text',
          ),
        );
      }
    } else if (!blank) {
      final t = TextObject(
        id: newId(),
        position: s.position,
        text: text,
        fontSize: s.fontSize,
        color: s.color,
        size: measureText(text, s.fontSize),
      );
      history.execute(AddObjects([t], label: 'Add text'));
    }
    _emit();
  }

  void cancelEdit() {
    editing = null;
    _emit();
  }

  // ---- commands ----

  void undo() {
    if (editing != null) return;
    if (history.undo()) _afterHistory();
  }

  void redo() {
    if (editing != null) return;
    if (history.redo()) _afterHistory();
  }

  void _afterHistory() {
    selection.removeWhere((id) => !document.contains(id));
    _emit();
  }

  void selectAll() {
    _tool = Tool.select;
    selection
      ..clear()
      ..addAll(document.order);
    _emit();
  }

  void clearSelection() {
    selection.clear();
    _emit();
  }

  void deleteSelection() {
    if (selection.isEmpty) return;
    history.execute(DeleteObjects(selection.toList()));
    selection.clear();
    _emit();
  }

  void nudge(Vec2 d) {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    history.execute(UpdateObjects.move(objs, d));
    _emit();
  }

  void duplicateSelection() {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    _insertCopies(objs, const Vec2(24, 24), label: 'Duplicate');
  }

  void reorderSelection(ZMove move) {
    if (selection.isEmpty) return;
    history.execute(ReorderObjects(selection, move));
    _emit();
  }

  void rename(String title) {
    final t = title.trim();
    if (t.isEmpty || t == document.title) return;
    history.execute(RenameBoard(t));
    _emit();
  }

  void _insertCopies(List<BoardObject> objs, Vec2 offset, {required String label}) {
    final copies = [for (final o in objs) o.withId(newId()).translate(offset)];
    history.execute(AddObjects(copies, label: label));
    _tool = Tool.select;
    selection
      ..clear()
      ..addAll(copies.map((o) => o.id));
    _emit();
  }

  // ---- clipboard (system clipboard, so it works across boards) ----

  String? copyPayload() {
    final objs = selectedObjects;
    if (objs.isEmpty) return null;
    return jsonEncode({
      'format': clipboardFormat,
      'objects': [for (final o in objs) o.toJson()],
    });
  }

  Future<void> copy() async {
    final payload = copyPayload();
    if (payload != null) await Clipboard.setData(ClipboardData(text: payload));
  }

  Future<void> cut() async {
    await copy();
    deleteSelection();
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    pasteText(text);
  }

  /// Pastes Local Board objects at the cursor, or plain text as a text object.
  void pasteText(String text) {
    final target = hoverScreen != null ? toWorld(hoverScreen!) : toWorld(Offset(viewSize.width / 2, viewSize.height / 2));
    try {
      final json = jsonDecode(text);
      if (json is Map && json['format'] == clipboardFormat && json['objects'] is List) {
        final objs = [
          for (final o in json['objects'] as List) BoardObject.fromJson((o as Map).cast<String, Object?>()),
        ];
        if (objs.isEmpty) return;
        final center = Bounds.union(objs.map((o) => o.bounds))!.center;
        _insertCopies(objs, target - center, label: 'Paste');
        return;
      }
    } on FormatException {
      // Not ours: fall through to plain text.
    }
    final t = TextObject(
      id: newId(),
      position: target,
      text: text,
      fontSize: _textSize,
      color: _color,
      size: measureText(text, _textSize),
    );
    history.execute(AddObjects([t], label: 'Paste text'));
    _tool = Tool.select;
    selection
      ..clear()
      ..add(t.id);
    _emit();
  }

  // ---- keyboard (plan §20) ----

  /// Returns true when the key was used. Ignored while a text editor is open
  /// so typing never triggers shortcuts.
  bool handleKey(KeyEvent event) {
    if (editing != null) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (!_spaceHeld) {
          _spaceHeld = true;
          _emit();
        }
      } else if (event is KeyUpEvent) {
        _spaceHeld = false;
        _emit();
      }
      return true;
    }
    if (event is KeyUpEvent) return false;

    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final shift = kb.isShiftPressed;

    if (ctrl) {
      switch (key) {
        case LogicalKeyboardKey.keyZ:
          shift ? redo() : undo();
        case LogicalKeyboardKey.keyY:
          redo();
        case LogicalKeyboardKey.keyC:
          copy();
        case LogicalKeyboardKey.keyX:
          cut();
        case LogicalKeyboardKey.keyV:
          paste();
        case LogicalKeyboardKey.keyA:
          selectAll();
        case LogicalKeyboardKey.keyD:
          duplicateSelection();
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.add:
        case LogicalKeyboardKey.numpadAdd:
          zoomBy(1.25);
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          zoomBy(0.8);
        case LogicalKeyboardKey.digit0:
        case LogicalKeyboardKey.numpad0:
          resetZoom();
        case LogicalKeyboardKey.bracketRight:
          reorderSelection(ZMove.toFront);
        case LogicalKeyboardKey.bracketLeft:
          reorderSelection(ZMove.toBack);
        default:
          return false;
      }
      return true;
    }

    switch (key) {
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        deleteSelection();
        return true;
      case LogicalKeyboardKey.escape:
        if (selection.isNotEmpty) {
          clearSelection();
        } else {
          setTool(Tool.select);
        }
        return true;
      case LogicalKeyboardKey.enter:
        final objs = selectedObjects;
        if (objs.length == 1 && (objs.first is TextObject || objs.first is StickyNote)) {
          beginEditObject(objs.first);
          return true;
        }
        return false;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
        if (selection.isEmpty) return false;
        // One screen pixel per press (ten with Shift), whatever the zoom.
        final step = (shift ? 10.0 : 1.0) / camera.zoom;
        nudge(switch (key) {
          LogicalKeyboardKey.arrowLeft => Vec2(-step, 0),
          LogicalKeyboardKey.arrowRight => Vec2(step, 0),
          LogicalKeyboardKey.arrowUp => Vec2(0, -step),
          _ => Vec2(0, step),
        });
        return true;
      case LogicalKeyboardKey.digit1 when shift:
        zoomToFit();
        return true;
    }
    if (!shift) {
      final t = Tool.forKey(key);
      if (t != null) {
        setTool(t);
        return true;
      }
    }
    return false;
  }
}
