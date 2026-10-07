import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:pasteboard/pasteboard.dart';

/// Picture types the board can show.
const imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];

/// Larger files are skipped instead of freezing the app while they load.
const _maxImageBytes = 64 * 1024 * 1024;

bool isImagePath(String path) {
  final dot = path.lastIndexOf('.');
  return dot >= 0 && imageExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Reads the picture files among [paths]; anything else is ignored.
Future<List<PastedImage>> readImageFiles(Iterable<String> paths) async {
  final out = <PastedImage>[];
  for (final path in paths) {
    if (!isImagePath(path)) continue;
    try {
      final file = File(path);
      if (await file.length() > _maxImageBytes) continue;
      out.add(PastedImage(await file.readAsBytes(), name: path.split(RegExp(r'[\\/]')).last));
    } on Object {
      // Unreadable file: skip it.
    }
  }
  return out;
}

/// "Insert image…": lets the user pick one or more picture files.
Future<List<PastedImage>> pickImages() async {
  final files = await openFiles(
    acceptedTypeGroups: [XTypeGroup(label: 'Images', extensions: imageExtensions)],
  );
  final out = <PastedImage>[];
  for (final f in files) {
    try {
      if (await f.length() > _maxImageBytes) continue;
      out.add(PastedImage(await f.readAsBytes(), name: f.name));
    } on Object {
      // Unreadable file: skip it.
    }
  }
  return out;
}

final _url = RegExp(r'^https?://\S+$', caseSensitive: false);

/// Reads the Windows/macOS/Linux clipboard for Ctrl+V.
///
/// What counts, in order: Local Board's own copied objects (plain text, so the
/// canvas handles them), picture files copied in the file manager, plain text,
/// and finally a bitmap. Text beats a bitmap because spreadsheets and some
/// apps put both on the clipboard when you copy text; a lone web address does
/// not, since browsers add it when you copy an image.
Future<ClipboardContent> readSystemClipboard() async {
  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  if (text != null && text.contains(BoardController.clipboardFormat)) return ClipboardContent(text: text);

  try {
    final files = await readImageFiles(await Pasteboard.files());
    if (files.isNotEmpty) return ClipboardContent(text: text, images: files);
  } on Object {
    // No file list on this clipboard.
  }

  final hasText = text != null && text.trim().isNotEmpty && !_url.hasMatch(text.trim());
  if (hasText) return ClipboardContent(text: text);

  try {
    final bitmap = await Pasteboard.image;
    if (bitmap != null && bitmap.isNotEmpty) {
      return ClipboardContent(text: text, images: [PastedImage(bitmap)]);
    }
  } on Object {
    // No bitmap on this clipboard.
  }
  return ClipboardContent(text: text);
}
