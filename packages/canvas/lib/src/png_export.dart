import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:local_board_core/local_board_core.dart';

import 'painter.dart';
import 'palette.dart';

/// Renders the whole board to PNG bytes (plan §14), fully offline.
/// [pixelRatio] is capped so huge boards do not exhaust memory.
Future<Uint8List> exportPng(
  BoardDocument doc, {
  double pixelRatio = 2,
  double padding = 32,
  bool background = true,
  double maxSide = 8192,
}) async {
  final content = (doc.contentBounds ?? const Bounds(0, 0, 800, 600)).inflate(padding);
  var ratio = pixelRatio;
  final longest = content.width > content.height ? content.width : content.height;
  if (longest * ratio > maxSide) ratio = maxSide / longest;

  final w = (content.width * ratio).ceil(), h = (content.height * ratio).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  canvas.translate(-content.left, -content.top);
  if (background) {
    canvas.drawRect(
      Rect.fromLTRB(content.left, content.top, content.right, content.bottom),
      Paint()..color = const Color(Palette.canvas),
    );
  }
  for (final o in doc.objects) {
    paintObject(canvas, o);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
