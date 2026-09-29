import 'dart:async';

import 'package:local_board_core/local_board_core.dart';

enum SaveStatus { saved, pending, saving, error }

/// Debounced autosave (plan §12): waits for a pause in editing, never runs
/// two saves at once, and can be flushed immediately on close/switch.
final class Autosaver {
  Autosaver({
    required this.document,
    required this.save,
    this.debounce = const Duration(milliseconds: 600),
    this.maxDelay = const Duration(seconds: 5),
    this.onStatus,
  }) : _savedRevision = document.saveRevision;

  final BoardDocument document;
  final Future<void> Function(BoardDocument) save;
  final Duration debounce;

  /// Continuous drawing never postpones a save longer than this.
  final Duration maxDelay;
  final void Function(SaveStatus status, Object? error)? onStatus;

  int _savedRevision;
  Timer? _timer;
  DateTime? _firstPending;
  Future<void>? _inFlight;
  bool _disposed = false;

  SaveStatus get status => _status;
  SaveStatus _status = SaveStatus.saved;
  Object? lastError;

  bool get isDirty => document.saveRevision != _savedRevision;

  /// Call after every change.
  void markDirty() {
    if (_disposed || !isDirty) return;
    _firstPending ??= DateTime.now();
    _set(SaveStatus.pending);
    _timer?.cancel();
    final waited = DateTime.now().difference(_firstPending!);
    final remaining = maxDelay - waited;
    _timer = Timer(remaining < debounce ? (remaining.isNegative ? Duration.zero : remaining) : debounce, _run);
  }

  /// Saves now if anything is pending and waits for it.
  Future<void> flush() async {
    _timer?.cancel();
    if (_inFlight != null) await _inFlight;
    if (isDirty) await _run();
  }

  Future<void> dispose() async {
    await flush();
    _disposed = true;
  }

  Future<void> _run() async {
    if (_inFlight != null) {
      await _inFlight;
      if (!isDirty) return;
    }
    final revision = document.saveRevision;
    _firstPending = null;
    _set(SaveStatus.saving);
    final future = save(document);
    _inFlight = future;
    try {
      await future;
      _savedRevision = revision;
      lastError = null;
      _set(isDirty ? SaveStatus.pending : SaveStatus.saved);
      if (isDirty && !_disposed) markDirty();
    } on Object catch (e) {
      lastError = e;
      _set(SaveStatus.error, e);
      // Retry later; the edits are still in memory.
      if (!_disposed) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 3), _run);
      }
    } finally {
      _inFlight = null;
    }
  }

  void _set(SaveStatus s, [Object? error]) {
    if (_status == s && error == null) return;
    _status = s;
    onStatus?.call(s, error);
  }
}
