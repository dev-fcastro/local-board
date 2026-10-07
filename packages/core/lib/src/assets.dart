import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'geometry.dart';

/// Binary content a board refers to (today: pasted or dropped images).
///
/// Assets are content-addressed: the id is a hash of the bytes, so the same
/// picture pasted twice, or in two boards, is stored once. The board JSON only
/// carries the id; the bytes live next to it on disk.
final class BoardAsset {
  const BoardAsset({required this.id, required this.mime, required this.bytes});

  /// Hashes [bytes]. [mime] is sniffed from the content when not given.
  factory BoardAsset.fromBytes(Uint8List bytes, {String? mime}) {
    final type = mime ?? sniffImageMime(bytes);
    if (type == null) throw const FormatException('Not a supported image');
    return BoardAsset(id: sha256.convert(bytes).toString().substring(0, 32), mime: type, bytes: bytes);
  }

  /// Ids are hex so they are always safe as file names, whatever a cloud
  /// storage or a shared file hands us.
  static final idPattern = RegExp(r'^[0-9a-f]{16,64}$');

  final String id;
  final String mime;
  final Uint8List bytes;

  String get extension => extensionForMime(mime);
  String get fileName => '$id.$extension';

  static const _mimes = {
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/bmp': 'bmp',
  };

  static String extensionForMime(String mime) => _mimes[mime] ?? 'bin';

  static String? mimeForExtension(String ext) {
    final e = ext.toLowerCase().replaceFirst('.', '');
    if (e == 'jpeg') return 'image/jpeg';
    for (final entry in _mimes.entries) {
      if (entry.value == e) return entry.key;
    }
    return null;
  }

  /// The image type of [b] judged by its magic bytes, or null when it is not
  /// a picture we can show (PNG, JPEG, GIF, WebP, BMP).
  static String? sniffImageMime(List<int> b) => sniffImageMimeImpl(b);

  Map<String, Object?> toEmbeddedJson() => {'mime': mime, 'data': base64Encode(bytes)};

  static BoardAsset? fromEmbeddedJson(String id, Object? json) {
    if (!idPattern.hasMatch(id) || json is! Map) return null;
    final data = json['data'], mime = json['mime'];
    if (data is! String || mime is! String) return null;
    try {
      return BoardAsset(id: id, mime: mime, bytes: base64Decode(data));
    } on FormatException {
      return null;
    }
  }
}

String? sniffImageMime(List<int> b) => BoardAsset.sniffImageMime(b);

String? sniffImageMimeImpl(List<int> b) {
  bool starts(List<int> sig, [int at = 0]) {
    if (b.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8)) return 'image/webp';
  if (starts(const [0x42, 0x4D])) return 'image/bmp';
  return null;
}

/// Size an image gets when it lands on the board: its natural size, shrunk to
/// fit within [fraction] of the visible area (in world units) and never above
/// [maxSide], so a 6000 px photo does not swallow the view.
Vec2 fitImageSize(Vec2 natural, Vec2 visible, {double fraction = 0.7, double maxSide = 4000}) {
  if (natural.x <= 0 || natural.y <= 0) return const Vec2(200, 200);
  var s = 1.0;
  if (visible.x > 0) s = s < visible.x * fraction / natural.x ? s : visible.x * fraction / natural.x;
  if (visible.y > 0) s = s < visible.y * fraction / natural.y ? s : visible.y * fraction / natural.y;
  final longest = natural.x > natural.y ? natural.x : natural.y;
  if (longest * s > maxSide) s = maxSide / longest;
  return Vec2(natural.x * s, natural.y * s);
}
