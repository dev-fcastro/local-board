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

  @override
  void apply(BoardDocument doc) {
    _removed.clear();
    // Remove top-down so the recorded indices are valid for bottom-up reinsertion.
    final sorted = ids.where(doc.contains).toList()..sort((a, b) => doc.indexOf(b).compareTo(doc.indexOf(a)));
    for (final id in sorted) {
      _removed.add(doc.removeById(id));
    }
  }

  @override
  void revert(BoardDocument doc) {
    for (final (index, object) in _removed.reversed) {
      doc.insertAt(index, object);
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

enum ZMove { toFront, toBack }

final class ReorderObjects implements Command {
  ReorderObjects(Iterable<String> ids, this.move) : ids = Set.unmodifiable(ids);

  final Set<String> ids;
  final ZMove move;
  List<String>? _previous;

  @override
  String get label => move == ZMove.toFront ? 'Bring to front' : 'Send to back';

  @override
  void apply(BoardDocument doc) {
    _previous = doc.order;
    final moving = _previous!.where(ids.contains).toList();
    final rest = _previous!.where((id) => !ids.contains(id)).toList();
    doc.setOrder(move == ZMove.toFront ? [...rest, ...moving] : [...moving, ...rest]);
  }

  @override
  void revert(BoardDocument doc) => doc.setOrder(_previous!);
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
