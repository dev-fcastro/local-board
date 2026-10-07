import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:local_board_core/local_board_core.dart';

/// Pixel size of encoded picture [bytes], or null when they cannot be decoded.
Future<Vec2?> decodeImageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Vec2(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    return size;
  } on Object {
    return null;
  }
}

/// Decoded pictures of one board, by asset id.
///
/// The painter asks synchronously ([lookup]) and gets null until the decode
/// finishes; listeners are told when something became available so the canvas
/// repaints. Decoding happens once per picture, not once per frame.
class BoardImageCache extends ChangeNotifier {
  BoardImageCache(this.document);

  final BoardDocument document;
  final Map<String, ui.Image> _ready = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  bool _disposed = false;

  /// The decoded picture, or null while it loads (or if it is missing/broken).
  ui.Image? lookup(String assetId) {
    final ready = _ready[assetId];
    if (ready != null) return ready;
    if (!_loading.contains(assetId) && !_failed.contains(assetId) && document.asset(assetId) != null) {
      unawaited(_decode(assetId));
    }
    return null;
  }

  bool isReady(String assetId) => _ready.containsKey(assetId);

  /// Decodes every picture the board uses; PNG export waits on this.
  Future<void> preload() async {
    for (final id in document.referencedAssetIds) {
      if (!_ready.containsKey(id) && document.asset(id) != null) await _decode(id);
    }
  }

  Future<void> _decode(String id) async {
    if (_loading.contains(id)) return;
    final asset = document.asset(id);
    if (asset == null) return;
    _loading.add(id);
    try {
      final codec = await ui.instantiateImageCodec(asset.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
      } else {
        _ready[id] = frame.image;
        notifyListeners();
      }
    } on Object {
      _failed.add(id);
    } finally {
      _loading.remove(id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _ready.values) {
      image.dispose();
    }
    _ready.clear();
    super.dispose();
  }
}

/// Re-encodes [bytes] as PNG, or null if they cannot be decoded. Bitmaps from
/// the Windows clipboard arrive as raw BMP (many MB); PNG keeps boards small.
Future<Uint8List?> encodePng(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } on Object {
    return null;
  }
}
