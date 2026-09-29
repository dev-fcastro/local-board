import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

import 'src/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = BoardStore(defaultDataDirectory());
  await store.init();

  // `local-board path/to/file.whiteboard` imports and opens that board.
  String? openId;
  final file = args.where((a) => a.endsWith(BoardStore.extension)).firstOrNull;
  if (file != null && File(file).existsSync()) {
    try {
      openId = (await store.importFrom(file)).id;
    } on Object catch (e) {
      stderr.writeln('Could not open $file: $e');
    }
  }

  runApp(LocalBoardApp(store: store, openBoardId: openId));
}
