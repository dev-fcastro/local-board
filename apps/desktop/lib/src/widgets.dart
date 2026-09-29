import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/logo.svg.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// Rounded pill button matching the site's download buttons.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    const ink = Color(Palette.ink);
    final style = ButtonStyle(
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
      side: const WidgetStatePropertyAll(BorderSide(color: ink)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered) ? const Color(Palette.accent) : (filled ? ink : Colors.transparent),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => filled || s.contains(WidgetState.hovered) ? Colors.white : ink,
      ),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
    );
    final button = TextButton.icon(
      onPressed: onPressed,
      style: style,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Small live preview of a board for the home grid.
class BoardThumbnail extends StatefulWidget {
  const BoardThumbnail({super.key, required this.store, required this.board});

  final BoardStore store;
  final BoardSummary board;

  @override
  State<BoardThumbnail> createState() => _BoardThumbnailState();
}

class _BoardThumbnailState extends State<BoardThumbnail> {
  BoardDocument? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BoardThumbnail old) {
    super.didUpdateWidget(old);
    if (old.board.updatedAt != widget.board.updatedAt || old.board.id != widget.board.id) _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.store.open(widget.board.id);
      if (mounted) setState(() => _doc = loaded.document);
    } on Object {
      // Leave the dotted placeholder.
    }
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ThumbPainter(_doc), child: const SizedBox.expand());
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.doc);

  final BoardDocument? doc;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Palette.canvas));
    final dot = Paint()..color = const Color(Palette.gridDot);
    for (var x = 8.0; x < size.width; x += 14) {
      for (var y = 8.0; y < size.height; y += 14) {
        canvas.drawCircle(Offset(x, y), 0.8, dot);
      }
    }
    final d = doc;
    final b = d?.contentBounds;
    if (d == null || b == null) return;
    final pad = 16.0;
    final scale = math.min(
      1.0,
      math.min((size.width - pad * 2) / math.max(1, b.width), (size.height - pad * 2) / math.max(1, b.height)),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-b.center.x, -b.center.y);
    for (final o in d.objects) {
      paintObject(canvas, o);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.doc != doc;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

Future<String?> promptText(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 360, child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

String relativeTime(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  final l = t.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[l.month - 1]} ${l.day}, ${l.year}';
}
