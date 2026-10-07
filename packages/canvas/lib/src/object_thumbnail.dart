import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:local_board_core/local_board_core.dart';

import 'image_cache.dart';
import 'painter.dart';

/// A small preview of one board object (the layers panel uses it).
class ObjectThumbnail extends StatelessWidget {
  const ObjectThumbnail({super.key, required this.object, required this.images, this.size = 34});

  final BoardObject object;
  final BoardImageCache images;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: images,
      builder: (_, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _ThumbPainter(object, images)),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.object, this.images);

  final BoardObject object;
  final BoardImageCache images;

  @override
  void paint(Canvas canvas, Size size) {
    final b = object.bounds;
    if (b.width <= 0 || b.height <= 0) return;
    const inset = 3.0;
    final avail = Size(size.width - inset * 2, size.height - inset * 2);
    final s = math.min(avail.width / b.width, avail.height / b.height);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(size.width / 2 - b.center.x * s, size.height / 2 - b.center.y * s)
      ..scale(s);
    paintObject(canvas, object, images: images);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => true;
}
