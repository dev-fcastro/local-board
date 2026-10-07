import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'tools.dart';

/// Radial tool picker ("weapon wheel") drawn over the canvas while Alt is held
/// and the mouse wheel turns. Purely visual: [BoardController] owns which tool
/// is highlighted, this widget animates towards [tool] and reports pointer
/// hover / clicks.
///
/// It stays in the tree after [open] turns false just long enough to play its
/// exit animation, and ignores pointers whenever it is closed.
class ToolWheelOverlay extends StatefulWidget {
  const ToolWheelOverlay({
    super.key,
    required this.open,
    required this.tool,
    required this.anchor,
    required this.onHover,
    required this.onSelect,
  });

  /// Whether the wheel is showing.
  final bool open;

  /// Highlighted tool. Only meaningful while open; the last value is kept
  /// during the exit animation.
  final Tool? tool;

  /// Where the wheel is centered (clamped so it always fits in the view).
  final Offset anchor;

  final ValueChanged<Tool> onHover;

  /// A click: on a sector picks it, anywhere else keeps the highlighted tool.
  final ValueChanged<Tool> onSelect;

  static const outerRadius = 148.0;
  static const innerRadius = 58.0;

  @override
  State<ToolWheelOverlay> createState() => _ToolWheelOverlayState();
}

class _ToolWheelOverlayState extends State<ToolWheelOverlay> with TickerProviderStateMixin {
  static const _tools = Tool.values;
  static const _enter = Duration(milliseconds: 140);
  static const _exit = Duration(milliseconds: 120);
  static const _turn = Duration(milliseconds: 150);

  late final AnimationController _appear = AnimationController(vsync: this, duration: _enter, reverseDuration: _exit);
  late final AnimationController _move = AnimationController(vsync: this, duration: _turn);
  final _ease = Curves.easeOutCubic;

  Tool _shown = Tool.select;
  Offset _center = Offset.zero;
  double _from = 0;
  double _to = 0;

  /// Highlight position in sector units, fractional while animating.
  double get _pos => _from + (_to - _from) * _ease.transform(_move.value);

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    if (widget.open) _show();
  }

  @override
  void didUpdateWidget(ToolWheelOverlay old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      _show();
    } else if (widget.open && widget.tool != null && widget.tool != _shown) {
      _retarget(widget.tool!);
    } else if (!widget.open && old.open) {
      _appear.reverse();
    }
  }

  void _show() {
    _center = widget.anchor;
    final t = widget.tool ?? _shown;
    _shown = t;
    _from = _to = _tools.indexOf(t).toDouble();
    _move.value = 1;
    _appear.duration = _reduceMotion ? Duration.zero : _enter;
    _appear.forward();
  }

  void _retarget(Tool t) {
    final cur = _pos;
    final n = _tools.length;
    var diff = (_tools.indexOf(t) - cur) % n;
    if (diff > n / 2) diff -= n;
    _shown = t;
    _from = cur;
    _to = cur + diff;
    if (_reduceMotion) {
      _from = _to;
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _move.dispose();
    super.dispose();
  }

  /// The sector under [p] (overlay coordinates), or null off the ring.
  Tool? _sectorAt(Offset p) {
    final d = p - _center;
    final dist = d.distance;
    if (dist < ToolWheelOverlay.innerRadius || dist > ToolWheelOverlay.outerRadius + 6) return null;
    final sector = 2 * math.pi / _tools.length;
    var a = math.atan2(d.dy, d.dx) + math.pi / 2; // 0 = straight up, clockwise
    a = (a + sector / 2) % (2 * math.pi);
    if (a < 0) a += 2 * math.pi;
    return _tools[(a / sector).floor() % _tools.length];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_appear, _move]),
      builder: (context, _) {
        if (_appear.isDismissed && !widget.open) return const SizedBox.shrink();
        final t = Curves.easeOut.transform(_appear.value);
        final pos = _pos;
        const r = ToolWheelOverlay.outerRadius;
        final tool = _shown;
        return Semantics(
          container: true,
          liveRegion: true,
          label: 'Tool wheel, ${tool.label}',
          child: IgnorePointer(
            ignoring: !widget.open,
            child: MouseRegion(
              onHover: (e) {
                final s = _sectorAt(e.localPosition);
                if (s != null) widget.onHover(s);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => widget.onSelect(_sectorAt(d.localPosition) ?? _shown),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // "Focus": blur and dim whatever is behind the wheel.
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3.5 * t, sigmaY: 3.5 * t),
                      child: ColoredBox(color: Color.fromRGBO(23, 24, 26, 0.12 * t)),
                    ),
                    Positioned(
                      left: _center.dx - r,
                      top: _center.dy - r,
                      width: r * 2,
                      height: r * 2,
                      child: Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: 0.86 + 0.14 * t,
                          child: _Wheel(pos: pos, tool: tool),
                        ),
                      ),
                    ),
                    Positioned(
                      left: _center.dx - 160,
                      width: 320,
                      top: _center.dy + r + 14,
                      child: Opacity(
                        opacity: t,
                        child: const Center(child: _Hint()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xE617181A), borderRadius: BorderRadius.circular(99)),
      child: const Text(
        'Scroll to switch · release Alt to pick · Esc to cancel',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({required this.pos, required this.tool});

  final double pos;
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    const tools = Tool.values;
    const r = ToolWheelOverlay.outerRadius;
    const inner = ToolWheelOverlay.innerRadius;
    const mid = (r + inner) / 2 + 2;
    final sector = 2 * math.pi / tools.length;
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _WheelPainter(pos))),
        for (var i = 0; i < tools.length; i++)
          () {
            // 1 when the highlight sits on this sector, 0 a sector away.
            var dist = (i - pos).abs() % tools.length;
            if (dist > tools.length / 2) dist = tools.length - dist;
            final k = (1 - dist).clamp(0.0, 1.0);
            final angle = -math.pi / 2 + i * sector;
            return Positioned(
              left: r + mid * math.cos(angle) - 20,
              top: r + mid * math.sin(angle) - 20,
              width: 40,
              height: 40,
              child: Transform.scale(
                scale: 1 + 0.3 * k,
                child: Icon(tools[i].icon, size: 22, color: Color.lerp(const Color(0x9917181A), Colors.white, k)),
              ),
            );
          }(),
        Positioned(
          left: r - inner,
          top: r - inner,
          width: inner * 2,
          height: inner * 2,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tool.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: Color(Palette.ink),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tool.shortcutLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamilyFallback: ['Space Mono', 'Consolas', 'monospace'],
                    color: Color(Palette.inkSecondary),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.pos);

  final double pos;

  static Path _annulus(Offset c, double outer, double inner, double start, double sweep) {
    return Path()
      ..arcTo(Rect.fromCircle(center: c, radius: outer), start, sweep, true)
      ..arcTo(Rect.fromCircle(center: c, radius: inner), start + sweep, -sweep, false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const outer = ToolWheelOverlay.outerRadius;
    const inner = ToolWheelOverlay.innerRadius;
    final n = Tool.values.length;
    final sector = 2 * math.pi / n;

    final ring = Path()
      ..addOval(Rect.fromCircle(center: c, radius: outer))
      ..addOval(Rect.fromCircle(center: c, radius: inner))
      ..fillType = PathFillType.evenOdd;
    canvas.drawShadow(ring, const Color(0xFF17181A), 14, false);
    canvas.drawPath(ring, Paint()..color = const Color(0xF5FFFFFF));

    // Hairlines between sectors.
    final line = Paint()
      ..color = const Color(0x2217181A)
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (i - 0.5) * sector;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * inner, c + Offset(math.cos(a), math.sin(a)) * outer, line);
    }

    // Highlight wedge: slides (rotates) with the animated position and bulges
    // slightly past the ring, which reads as "scaled".
    final start = -math.pi / 2 + (pos - 0.5) * sector;
    final wedge = _annulus(c, outer + 6, inner - 2, start + 0.012, sector - 0.024);
    canvas.drawShadow(wedge, const Color(0xFF4F46E5), 8, false);
    canvas.drawPath(wedge, Paint()..color = const Color(Palette.accent));

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x3317181A);
    canvas.drawCircle(c, outer, edge);
    canvas.drawCircle(c, inner, edge);
    canvas.drawCircle(c, inner - 3, Paint()..color = const Color(0xFFFAF9F9));
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.pos != pos;
}
