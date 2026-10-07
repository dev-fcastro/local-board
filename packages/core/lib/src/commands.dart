import 'document.dart';
import 'geometry.dart';
import 'objects.dart';

/// A reversible change to a [BoardDocument]. Every edit goes through one so
/// undo/redo, autosave and (later) sync all see the same stream of changes.
abstract interface class Command {
  String get label;
  void apply(BoardDocument doc);
  void revert(BoardDocument doc);
}

/// Adds objects on top (or at explicit indices when re-inserting).
final class AddObjects implements Command {
  AddObjects(List<BoardObject> objects, {this.label = 'Add'}) : objects = List.unmodifiable(objects);

  @override
  final String label;
  final List<BoardObject> objects;

  @override
  void apply(BoardDocument doc) {
    for (final o in objects) {
      doc.insertAt(doc.length, o);
    }
  }

  @override
  void revert(BoardDocument doc) {
    for (final o in objects.reversed) {
      doc.removeById(o.id);
    }
  }
}

/// Removes objects, remembering their z-index so undo restores the stacking.
final class DeleteObjects implements Command {
  DeleteObjects(Iterable<String> ids, {this.label = 'Delete'}) : ids = List.unmodifiable(ids);

  @override
  final String label;
  final List<String> ids;
  final List<(int, BoardObject)> _removed = [];
  final Map<String, LayerProps> _removedProps = {};

  @override
  void apply(BoardDocument doc) {
    _removed.clear();
    _removedProps.clear();
    // Remove top-down so the recorded indices are valid for bottom-up reinsertion.
    final sorted = ids.where(doc.contains).toList()..sort((a, b) => doc.indexOf(b).compareTo(doc.indexOf(a)));
    for (final id in sorted) {
      final props = doc.propsOf(id);
      if (!props.isDefault) _removedProps[id] = props;
      _removed.add(doc.removeById(id));
    }
  }

  @override
  void revert(BoardDocument doc) {
    for (final (index, object) in _removed.reversed) {
      doc.insertAt(index, object);
      final props = _removedProps[object.id];
      if (props != null) doc.setProps(object.id, props);
    }
  }
}

/// Swaps object states: covers move, resize, text edit and style changes.
final class UpdateObjects implements Command {
  UpdateObjects({required List<BoardObject> before, required List<BoardObject> after, this.label = 'Edit'})
    : before = List.unmodifiable(before),
      after = List.unmodifiable(after) {
    if (before.length != after.length) throw ArgumentError('before/after length mismatch');
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id) throw ArgumentError('before/after ids must match pairwise');
    }
  }

  factory UpdateObjects.move(List<BoardObject> objects, Vec2 delta) =>
      UpdateObjects(before: objects, after: [for (final o in objects) o.translate(delta)], label: 'Move');

  @override
  final String label;
  final List<BoardObject> before;
  final List<BoardObject> after;

  @override
  void apply(BoardDocument doc) => after.forEach(doc.replace);

  @override
  void revert(BoardDocument doc) => before.forEach(doc.replace);
}

enum ZMove {
  toFront('Bring to front'),
  toBack('Send to back'),
  forward('Bring forward'),
  backward('Send backward');

  const ZMove(this.label);
  final String label;
}

/// The stacking [order] (bottom first) after moving [ids] by [move].
/// Selected layers keep their relative order; one step moves each block past
/// the nearest layer that is not part of the selection.
List<String> reorderedIds(List<String> order, Set<String> ids, ZMove move) {
  final out = [...order];
  switch (move) {
    case ZMove.toFront:
      return [...order.where((id) => !ids.contains(id)), ...order.where(ids.contains)];
    case ZMove.toBack:
      return [...order.where(ids.contains), ...order.where((id) => !ids.contains(id))];
    case ZMove.forward:
      for (var i = out.length - 2; i >= 0; i--) {
        if (ids.contains(out[i]) && !ids.contains(out[i + 1])) {
          final t = out[i];
          out[i] = out[i + 1];
          out[i + 1] = t;
        }
      }
    case ZMove.backward:
      for (var i = 1; i < out.length; i++) {
        if (ids.contains(out[i]) && !ids.contains(out[i - 1])) {
          final t = out[i];
          out[i] = out[i - 1];
          out[i - 1] = t;
        }
      }
  }
  return out;
}

final class ReorderObjects implements Command {
  ReorderObjects(Iterable<String> ids, this.move) : ids = Set.unmodifiable(ids);

  final Set<String> ids;
  final ZMove move;
  List<String>? _previous;

  @override
  String get label => move.label;

  @override
  void apply(BoardDocument doc) {
    _previous = doc.order;
    doc.setOrder(reorderedIds(_previous!, ids, move));
  }

  @override
  void revert(BoardDocument doc) => doc.setOrder(_previous!);
}

/// Puts the whole stack in a given order (drag and drop in the layers panel).
final class SetOrder implements Command {
  SetOrder(Iterable<String> order, {this.label = 'Reorder layers'}) : order = List.unmodifiable(order);

  @override
  final String label;
  final List<String> order;
  List<String>? _previous;

  @override
  void apply(BoardDocument doc) {
    _previous = doc.order;
    doc.setOrder(order);
  }

  @override
  void revert(BoardDocument doc) => doc.setOrder(_previous!);
}

/// Renames, hides/shows or locks/unlocks layers.
final class SetLayerProps implements Command {
  SetLayerProps(Map<String, LayerProps> after, {required this.label}) : after = Map.unmodifiable(after);

  @override
  final String label;
  final Map<String, LayerProps> after;
  final Map<String, LayerProps> _before = {};

  @override
  void apply(BoardDocument doc) {
    _before.clear();
    for (final e in after.entries) {
      if (!doc.contains(e.key)) continue;
      _before[e.key] = doc.propsOf(e.key);
      doc.setProps(e.key, e.value);
    }
  }

  @override
  void revert(BoardDocument doc) {
    for (final e in _before.entries) {
      if (doc.contains(e.key)) doc.setProps(e.key, e.value);
    }
  }
}

final class RenameBoard implements Command {
  RenameBoard(this.title);

  final String title;
  String? _previous;

  @override
  String get label => 'Rename';

  @override
  void apply(BoardDocument doc) {
    _previous = doc.title;
    doc.rename(title);
  }

  @override
  void revert(BoardDocument doc) => doc.rename(_previous!);
}

/// Several commands as one undo step.
final class CompositeCommand implements Command {
  CompositeCommand(List<Command> commands, {required this.label}) : commands = List.unmodifiable(commands);

  @override
  final String label;
  final List<Command> commands;

  @override
  void apply(BoardDocument doc) {
    for (final c in commands) {
      c.apply(doc);
    }
  }

  @override
  void revert(BoardDocument doc) {
    for (final c in commands.reversed) {
      c.revert(doc);
    }
  }
}
