import 'package:flutter/painting.dart';
import 'package:local_board_core/local_board_core.dart';

TextStyle boardTextStyle(double fontSize, int color) => TextStyle(
  fontSize: fontSize,
  height: BoardStyle.lineHeight,
  color: Color(color),
  fontFamilyFallback: const ['Space Grotesk', 'Inter', 'Cantarell', 'Noto Sans', 'DejaVu Sans'],
);

/// Size of [text] as the canvas will render it. Stored on the TextObject so
/// the pure-Dart domain can hit-test without a text engine.
Vec2 measureText(String text, double fontSize) {
  final tp = TextPainter(
    text: TextSpan(text: text.isEmpty ? ' ' : text, style: boardTextStyle(fontSize, 0xFF000000)),
    textDirection: TextDirection.ltr,
  )..layout();
  final size = Vec2(tp.width.ceilToDouble() + 2, tp.height.ceilToDouble());
  tp.dispose();
  return size;
}
