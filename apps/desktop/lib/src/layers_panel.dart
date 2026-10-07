import 'package:flutter/material.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';

import 'toolbar.dart';

const _line = Color(0x3817181A);

/// Side panel with the board's layers, top of the stack first. Drag a row to
/// restack, click to select, double-click the name to rename; the eye hides a
/// layer and the padlock locks it so you can draw over it without moving it.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.controller, required this.onClose});

  static const width = 268.0;

  final BoardController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final doc = c.document;
    final layers = doc.layersTopDown;
    final hasSelection = c.selection.isNotEmpty;

    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: SizedBox(
        width: width - 20,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Text(
                    'LAYERS',
                    style: TextStyle(fontSize: 10, letterSpacing: 0.8, color: Color(Palette.inkSecondary)),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${layers.length}', style: const TextStyle(fontSize: 10, color: Color(Palette.inkTertiary))),
                const Spacer(),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    tooltip: 'Close layers',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Color(Palette.inkSecondary)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (layers.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(2, 8, 2, 14),
                child: Text(
                  'Nothing here yet. Draw something, or paste an image with Ctrl+V.',
                  style: TextStyle(fontSize: 12, color: Color(Palette.inkSecondary)),
                ),
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: layers.length,
                  proxyDecorator: (child, _, _) => Material(
                    color: Colors.white,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  ),
                  onReorderItem: (from, to) {
                    // The list shows the top first; the document order is bottom first.
                    c.moveLayer(layers[from].id, layers.length - 1 - to);
                  },
                  itemBuilder: (context, i) {
                    final o = layers[i];
                    return LayerRow(
                      key: ValueKey(o.id),
                      index: i,
                      controller: c,
                      object: o,
                      name: doc.layerName(o.id),
                      customName: doc.propsOf(o.id).name,
                      visible: doc.isVisible(o.id),
                      locked: doc.isLocked(o.id),
                      selected: c.selection.contains(o.id),
                    );
                  },
                ),
              ),
            const Divider(height: 10),
            Row(
              children: [
                IconBtn(
                  icon: Icons.flip_to_front,
                  tooltip: 'Bring to front (Ctrl+])',
                  onPressed: hasSelection ? () => c.reorderSelection(ZMove.toFront) : null,
                ),
                IconBtn(
                  icon: Icons.arrow_upward,
                  tooltip: 'Bring forward (])',
                  onPressed: hasSelection ? () => c.reorderSelection(ZMove.forward) : null,
                ),
                IconBtn(
                  icon: Icons.arrow_downward,
                  tooltip: 'Send backward ([)',
                  onPressed: hasSelection ? () => c.reorderSelection(ZMove.backward) : null,
                ),
                IconBtn(
                  icon: Icons.flip_to_back,
                  tooltip: 'Send to back (Ctrl+[)',
                  onPressed: hasSelection ? () => c.reorderSelection(ZMove.toBack) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LayerRow extends StatefulWidget {
  const LayerRow({
    super.key,
    required this.index,
    required this.controller,
    required this.object,
    required this.name,
    required this.customName,
    required this.visible,
    required this.locked,
    required this.selected,
  });

  final int index;
  final BoardController controller;
  final BoardObject object;
  final String name;
  final String? customName;
  final bool visible;
  final bool locked;
  final bool selected;

  @override
  State<LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<LayerRow> {
  bool _editing = false;
  late final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'layer-name');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startRename() {
    _text
      ..text = widget.name
      ..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    if (!_editing) return;
    setState(() => _editing = false);
    // An unchanged name stays "automatic"; emptying the field restores it.
    final t = _text.text.trim();
    if (t != widget.name) widget.controller.renameLayer(widget.object.id, t);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final id = widget.object.id;
    const ink = Color(Palette.ink);
    const quiet = Color(Palette.inkTertiary);

    return Opacity(
      opacity: widget.visible ? 1 : 0.5,
      child: Container(
        height: 46,
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: widget.selected ? const Color(0x144F46E5) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.selected ? const Color(0x664F46E5) : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => c.selectLayer(id),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: widget.index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Icon(Icons.drag_indicator, size: 16, color: quiet),
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: _line),
                ),
                clipBehavior: Clip.antiAlias,
                child: ObjectThumbnail(object: widget.object, images: c.images, size: 34),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _text,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration.collapsed(hintText: 'Layer name'),
                        onSubmitted: (_) => _commit(),
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: _startRename,
                        child: Tooltip(
                          message: 'Double-click to rename',
                          waitDuration: const Duration(milliseconds: 800),
                          child: Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: ink),
                          ),
                        ),
                      ),
              ),
              _RowIcon(
                icon: widget.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                tooltip: widget.visible ? 'Hide layer' : 'Show layer',
                color: widget.visible ? quiet : const Color(Palette.accent),
                onPressed: () => c.setLayerVisible(id, !widget.visible),
              ),
              _RowIcon(
                icon: widget.locked ? Icons.lock_outline : Icons.lock_open_outlined,
                tooltip: widget.locked ? 'Unlock layer' : 'Lock layer (draw over it without moving it)',
                color: widget.locked ? const Color(Palette.accent) : quiet,
                onPressed: () => c.setLayerLocked(id, !widget.locked),
              ),
              _RowIcon(
                icon: Icons.delete_outline,
                tooltip: 'Delete layer',
                color: quiet,
                onPressed: () => c.deleteLayer(id),
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.tooltip, required this.color, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 30,
    child: IconButton(
      padding: EdgeInsets.zero,
      iconSize: 16,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color),
    ),
  );
}
