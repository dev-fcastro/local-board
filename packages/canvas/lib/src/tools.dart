import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum Tool {
  select('Select', 'V', LogicalKeyboardKey.keyV, Icons.near_me_outlined),
  hand('Hand', 'H', LogicalKeyboardKey.keyH, Icons.pan_tool_outlined),
  pen('Pen', 'P', LogicalKeyboardKey.keyP, Icons.edit_outlined),
  eraser('Eraser', 'E', LogicalKeyboardKey.keyE, Icons.cleaning_services_outlined),
  line('Line', 'L', LogicalKeyboardKey.keyL, Icons.horizontal_rule),
  arrow('Arrow', 'A', LogicalKeyboardKey.keyA, Icons.arrow_right_alt),
  rectangle('Rectangle', 'R', LogicalKeyboardKey.keyR, Icons.crop_square),
  ellipse('Ellipse', 'O', LogicalKeyboardKey.keyO, Icons.circle_outlined),
  text('Text', 'T', LogicalKeyboardKey.keyT, Icons.text_fields),
  sticky('Sticky note', 'N', LogicalKeyboardKey.keyN, Icons.sticky_note_2_outlined),
  component('Component', 'C', LogicalKeyboardKey.keyC, Icons.category_outlined);

  const Tool(this.label, this.shortcutLabel, this.key, this.icon);

  final String label;
  final String shortcutLabel;
  final LogicalKeyboardKey key;

  /// Icon shared by the tool dock and the tool wheel.
  final IconData icon;

  bool get isShape => this == line || this == arrow || this == rectangle || this == ellipse;
  bool get usesStroke => this == pen || isShape;

  static Tool? forKey(LogicalKeyboardKey key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}
