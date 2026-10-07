import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_board_core/local_board_core.dart';

import 'controller.dart';
import 'component_painter.dart';
import 'painter.dart';
import 'palette.dart';
import 'text_layout.dart';
import 'tools.dart';

/// The infinite canvas. Owns no board state: everything lives in
/// [BoardController], this widget only translates input and paints.
class BoardCanvas extends StatefulWidget {
  const BoardCanvas({super.key, required this.controller, this.focusNode, this.autofocus = true});

  final BoardController controller;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<BoardCanvas> {
  late FocusNode _focus = widget.focusNode ?? FocusNode(debugLabel: 'board');
  bool _ownsFocus = true;
  bool _placedInitialView = false;

  BoardController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    c.addListener(_onChange);
  }

  @override
  void didUpdateWidget(BoardCanvas old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      _placedInitialView = false;
    }
    if (old.focusNode != widget.focusNode) {
      if (_ownsFocus) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode(debugLabel: 'board');
      _ownsFocus = widget.focusNode == null;
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (c.editing == null && !_focus.hasFocus) _focus.requestFocus();
  }

  MouseCursor get _cursor {
    if (c.isPanning) return SystemMouseCursors.grabbing;
    if (c.spaceHeld || c.tool == Tool.hand) return SystemMouseCursors.grab;
    return switch (c.tool) {
      Tool.select => _hoverCursor(),
      Tool.text => SystemMouseCursors.text,
      Tool.eraser => SystemMouseCursors.disappearing,
      Tool.component => SystemMouseCursors.copy,
      _ => SystemMouseCursors.precise,
    };
  }

  MouseCursor _hoverCursor() {
    final h = c.hoverScreen;
    if (h == null) return SystemMouseCursors.basic;
    return switch (c.handleAt(h)) {
      Handle.topLeft || Handle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      Handle.topRight || Handle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      null => SystemMouseCursors.basic,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        c.viewSize = size;
        if (!_placedInitialView) {
          _placedInitialView = true;
          // A board without a saved camera opens framed (empty → origin
          // centered, content → fit). Others reopen exactly where they were
          // left, since the camera is saved with the board.
          if (c.camera == const Camera()) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (c.document.isEmpty) {
                c.setCamera(Camera(pan: Vec2(size.width / 2, size.height / 3)));
              } else {
                c.zoomToFit();
              }
            });
          }
        }
        return Focus(
          focusNode: _focus,
          autofocus: widget.autofocus,
          onKeyEvent: (_, e) => c.handleKey(e) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: MouseRegion(
            cursor: _cursor,
            onExit: (_) => c.pointerExit(),
            onHover: (e) {
              c.pointerHover(e.localPosition);
              if (c.tool == Tool.select) setState(() {}); // cursor over handles
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                _focus.requestFocus();
                c.pointerDown(e.localPosition, buttons: e.buttons, shift: HardwareKeyboard.instance.isShiftPressed);
              },
              onPointerMove: (e) => c.pointerMove(e.localPosition, shift: HardwareKeyboard.instance.isShiftPressed),
              onPointerUp: (_) => c.pointerUp(),
              onPointerCancel: (_) => c.pointerCancel(),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(e, (event) {
                    final s = event as PointerScrollEvent;
                    c.scroll(s.localPosition, s.scrollDelta);
                  });
                } else if (e is PointerScaleEvent) {
                  c.zoomBy(e.scale, focal: e.localPosition);
                }
              },
              onPointerPanZoomUpdate: (e) => c.trackpad(e.localPosition, e.panDelta, e.scale == 1 ? 1 : 1 + (e.scale - 1) * 0.1),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: BoardPainter(
                          BoardScene(
                            document: c.document,
                            viewport: c.camera,
                            preview: c.preview,
                            erasing: c.erasing,
                            hidden: c.editing?.isLabel == true ? null : c.editing?.objectId,
                            blankLabel: c.editing?.isLabel == true ? c.editing?.objectId : null,
                            draft: c.draft,
                            selection: c.selection,
                            selectionBounds: c.tool == Tool.select && !c.isInteracting && c.canTransformSelection
                                ? c.selectionBounds
                                : null,
                            images: c.images,
                            marquee: c.marquee,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (c.editing != null) _TextEditorOverlay(key: ValueKey(c.editing), controller: c),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// In-place editor for text objects and sticky notes, drawn at world scale.
class _TextEditorOverlay extends StatefulWidget {
  const _TextEditorOverlay({super.key, required this.controller});

  final BoardController controller;

  @override
  State<_TextEditorOverlay> createState() => _TextEditorOverlayState();
}

class _TextEditorOverlayState extends State<_TextEditorOverlay> {
  late final TextEditingController _text = TextEditingController(text: widget.controller.editing!.initialText);
  final FocusNode _focus = FocusNode(debugLabel: 'board-text');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.controller.commitEdit(_text.text);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.editing!;
    final zoom = c.camera.zoom;
    final origin = c.toScreen(s.position);

    final Widget editor;
    final label = s.label;
    if (label != null) {
      final component = s.objectId == null ? null : c.document[s.objectId!];
      final zone = component is ComponentObject && component.isZone;
      final style = component is ComponentObject
          ? componentLabelStyle(component)
          : boardTextStyle(ComponentStyle.labelFontSize, ComponentStyle.labelColor);
      editor = SizedBox(
        width: label.width,
        height: label.height,
        child: Align(
          alignment: zone ? Alignment.centerLeft : Alignment.center,
          child: _field(style, align: zone ? TextAlign.left : TextAlign.center, singleLine: true),
        ),
      );
    } else if (s.sticky) {
      editor = Container(
        width: s.stickySize.x,
        height: s.stickySize.y,
        padding: const EdgeInsets.all(BoardStyle.stickyPadding),
        decoration: BoxDecoration(
          color: Color(s.color),
          borderRadius: BorderRadius.circular(2),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: _field(boardTextStyle(BoardStyle.stickyFontSize, Palette.ink), expands: true),
      );
    } else {
      editor = IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40),
          child: _field(boardTextStyle(s.fontSize, s.color)),
        ),
      );
    }

    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: Transform.scale(
        scale: zoom,
        alignment: Alignment.topLeft,
        child: Material(type: MaterialType.transparency, child: editor),
      ),
    );
  }

  Widget _field(TextStyle style, {bool expands = false, TextAlign align = TextAlign.start, bool singleLine = false}) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _done = true;
          widget.controller.commitEdit(_text.text);
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _commit,
      },
      child: TextField(
        controller: _text,
        focusNode: _focus,
        style: style,
        cursorColor: const Color(Palette.accent),
        maxLines: singleLine ? 1 : null,
        expands: expands,
        textAlign: align,
        keyboardType: singleLine ? TextInputType.text : TextInputType.multiline,
        onSubmitted: singleLine ? (_) => _commit() : null,
        decoration: InputDecoration.collapsed(hintText: singleLine ? 'Name' : 'Type…'),
      ),
    );
  }
}
