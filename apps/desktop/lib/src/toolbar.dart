import 'package:flutter/material.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

const _line = Color(0x3817181A);

/// Floating white panel used for every piece of editor chrome.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(4)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
        boxShadow: const [BoxShadow(color: Color(0x1417181A), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, required this.tooltip, this.onPressed, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? const Color(Palette.accent) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 19,
            color: active
                ? Colors.white
                : onPressed == null
                ? const Color(Palette.inkTertiary)
                : const Color(Palette.ink),
          ),
        ),
      ),
    );
  }
}

class SaveIndicator extends StatelessWidget {
  const SaveIndicator({super.key, required this.status, this.cloud = false});

  final SaveStatus status;

  /// A cloud storage keeps a synced copy.
  final bool cloud;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SaveStatus.saved => ('Saved', const Color(0xFF16A34A)),
      SaveStatus.pending || SaveStatus.saving => ('Saving…', const Color(Palette.inkTertiary)),
      SaveStatus.error => ('Not saved — retrying', const Color(0xFFDC2626)),
    };
    return Tooltip(
      message: cloud
          ? 'Saved on this computer, with a synced copy in your cloud storage.'
          : 'Saved on this computer only. No internet needed.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(Palette.inkSecondary))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(99)),
            child: Text(cloud ? 'Synced' : 'Offline', style: const TextStyle(fontSize: 11, color: Color(Palette.inkSecondary))),
          ),
        ],
      ),
    );
  }
}

const _toolIcons = <Tool, IconData>{
  Tool.select: Icons.near_me_outlined,
  Tool.hand: Icons.pan_tool_outlined,
  Tool.pen: Icons.edit_outlined,
  Tool.eraser: Icons.cleaning_services_outlined,
  Tool.line: Icons.horizontal_rule,
  Tool.arrow: Icons.arrow_right_alt,
  Tool.rectangle: Icons.crop_square,
  Tool.ellipse: Icons.circle_outlined,
  Tool.text: Icons.text_fields,
  Tool.sticky: Icons.sticky_note_2_outlined,
  Tool.component: Icons.category_outlined,
};

/// Bottom tool dock, like the site mockup: "Select Pen Shape Text".
class ToolDock extends StatelessWidget {
  const ToolDock({super.key, required this.controller, this.libraryOpen = false, this.onLibrary});

  final BoardController controller;

  /// Opens and closes the component library.
  final VoidCallback? onLibrary;
  final bool libraryOpen;

  @override
  Widget build(BuildContext context) {
    final groups = [
      [Tool.select, Tool.hand],
      [Tool.pen, Tool.eraser],
      [Tool.line, Tool.arrow, Tool.rectangle, Tool.ellipse],
      [Tool.text, Tool.sticky],
    ];
    return Panel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) const SizedBox(height: 24, child: VerticalDivider(width: 12)),
            for (final t in groups[g])
              IconBtn(
                icon: _toolIcons[t]!,
                tooltip: '${t.label}  ${t.shortcutLabel}',
                active: controller.tool == t,
                onPressed: () => controller.setTool(t),
              ),
          ],
          if (onLibrary != null) ...[
            const SizedBox(height: 24, child: VerticalDivider(width: 12)),
            IconBtn(
              icon: _toolIcons[Tool.component]!,
              tooltip: 'Components  ${Tool.component.shortcutLabel}',
              active: libraryOpen,
              onPressed: onLibrary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Contextual style options: only shows what applies to the current tool or
/// selection (plan §19: "advanced tools appear contextually").
class StylePanel extends StatelessWidget {
  const StylePanel({super.key, required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final sel = c.selectedObjects;
    final tool = c.tool;

    final showInk = tool.usesStroke || tool == Tool.text || sel.any((o) => o is! StickyNote);
    final showWidth = tool.usesStroke || sel.any((o) => o is StrokeObject || o is ShapeObject);
    final showText = tool == Tool.text || sel.any((o) => o is TextObject);
    final showSticky = tool == Tool.sticky || sel.any((o) => o is StickyNote);
    final showArrange = sel.isNotEmpty && tool == Tool.select;
    if (!showInk && !showWidth && !showText && !showSticky && !showArrange) return const SizedBox.shrink();

    return Panel(
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: 172,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showInk) ...[
              const _Label('Color'),
              _Swatches(colors: Palette.inks, selected: c.color, onPick: c.setColor),
            ],
            if (showSticky) ...[
              const _Label('Note color'),
              _Swatches(colors: Palette.stickies, selected: c.stickyColor, onPick: c.setStickyColor),
            ],
            if (showWidth) ...[
              const _Label('Stroke'),
              _Segmented(
                values: Palette.strokeWidths,
                selected: c.strokeWidth,
                onPick: c.setStrokeWidth,
                builder: (w) => Container(
                  width: 22,
                  height: w.clamp(1.5, 7),
                  decoration: BoxDecoration(color: const Color(Palette.ink), borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ],
            if (showText) ...[
              const _Label('Text size'),
              _Segmented(
                values: Palette.textSizes,
                selected: c.textSize,
                onPick: c.setTextSize,
                builder: (s) => Text(s == 16 ? 'S' : s == 24 ? 'M' : 'L', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
            if (showArrange) ...[
              const _Label('Arrange'),
              Row(
                children: [
                  IconBtn(
                    icon: Icons.flip_to_front,
                    tooltip: 'Bring to front (Ctrl+])',
                    onPressed: () => c.reorderSelection(ZMove.toFront),
                  ),
                  IconBtn(
                    icon: Icons.flip_to_back,
                    tooltip: 'Send to back (Ctrl+[)',
                    onPressed: () => c.reorderSelection(ZMove.toBack),
                  ),
                  IconBtn(icon: Icons.copy_all_outlined, tooltip: 'Duplicate (Ctrl+D)', onPressed: c.duplicateSelection),
                  IconBtn(icon: Icons.delete_outline, tooltip: 'Delete (Del)', onPressed: c.deleteSelection),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 10, letterSpacing: 0.8, color: Color(Palette.inkSecondary)),
    ),
  );
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors, required this.selected, required this.onPick});

  final List<int> colors;
  final int selected;
  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final col in colors)
          InkWell(
            onTap: () => onPick(col),
            customBorder: const CircleBorder(),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Color(col),
                shape: BoxShape.circle,
                border: Border.all(
                  color: col == selected ? const Color(Palette.accent) : _line,
                  width: col == selected ? 2.5 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.values, required this.selected, required this.onPick, required this.builder});

  final List<double> values;
  final double selected;
  final void Function(double) onPick;
  final Widget Function(double) builder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final v in values)
          Expanded(
            child: InkWell(
              onTap: () => onPick(v),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 30,
                margin: const EdgeInsets.only(right: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: v == selected ? const Color(Palette.accent) : _line),
                  color: v == selected ? const Color(0x144F46E5) : null,
                ),
                child: builder(v),
              ),
            ),
          ),
      ],
    );
  }
}

class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Panel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBtn(icon: Icons.remove, tooltip: 'Zoom out (Ctrl+−)', onPressed: () => c.zoomBy(0.8)),
          Tooltip(
            message: 'Reset to 100% (Ctrl+0)',
            child: InkWell(
              onTap: c.resetZoom,
              child: SizedBox(
                width: 52,
                child: Text(
                  '${(c.camera.zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ),
          IconBtn(icon: Icons.add, tooltip: 'Zoom in (Ctrl++)', onPressed: () => c.zoomBy(1.25)),
          IconBtn(icon: Icons.fit_screen_outlined, tooltip: 'Fit to content (Shift+1)', onPressed: c.zoomToFit),
        ],
      ),
    );
  }
}
