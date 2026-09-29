import 'package:flutter/services.dart';

enum Tool {
  select('Select', 'V', LogicalKeyboardKey.keyV),
  hand('Hand', 'H', LogicalKeyboardKey.keyH),
  pen('Pen', 'P', LogicalKeyboardKey.keyP),
  eraser('Eraser', 'E', LogicalKeyboardKey.keyE),
  line('Line', 'L', LogicalKeyboardKey.keyL),
  arrow('Arrow', 'A', LogicalKeyboardKey.keyA),
  rectangle('Rectangle', 'R', LogicalKeyboardKey.keyR),
  ellipse('Ellipse', 'O', LogicalKeyboardKey.keyO),
  text('Text', 'T', LogicalKeyboardKey.keyT),
  sticky('Sticky note', 'N', LogicalKeyboardKey.keyN);

  const Tool(this.label, this.shortcutLabel, this.key);

  final String label;
  final String shortcutLabel;
  final LogicalKeyboardKey key;

  bool get isShape => this == line || this == arrow || this == rectangle || this == ellipse;
  bool get usesStroke => this == pen || isShape;

  static Tool? forKey(LogicalKeyboardKey key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}
