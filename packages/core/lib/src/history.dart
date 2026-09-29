import 'commands.dart';
import 'document.dart';

/// Command-based undo/redo (plan §9): stores reversible commands, not
/// document snapshots, so memory grows with edits rather than board size.
final class History {
  History(this.document, {this.limit = 500});

  final BoardDocument document;
  final int limit;

  final List<Command> _undo = [];
  final List<Command> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Applies [command] and records it. A new edit invalidates the redo stack.
  void execute(Command command) {
    command.apply(document);
    _undo.add(command);
    _redo.clear();
    if (_undo.length > limit) _undo.removeAt(0);
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final c = _undo.removeLast()..revert(document);
    _redo.add(c);
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final c = _redo.removeLast()..apply(document);
    _undo.add(c);
    return true;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
