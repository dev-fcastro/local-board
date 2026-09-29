import 'package:flutter/material.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

import 'editor_screen.dart';
import 'home_screen.dart';

const appVersion = '0.1.0';

ThemeData buildTheme() {
  const ink = Color(Palette.ink);
  const accent = Color(Palette.accent);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      primary: accent,
      surface: const Color(Palette.canvas),
      onSurface: ink,
    ),
    scaffoldBackgroundColor: const Color(Palette.canvas),
    fontFamilyFallback: const ['Space Grotesk', 'Inter', 'Cantarell', 'Noto Sans', 'DejaVu Sans'],
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    dividerTheme: const DividerThemeData(color: Color(0x3817181A), thickness: 1, space: 1),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
      decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.all(Radius.circular(4))),
      textStyle: TextStyle(color: Colors.white, fontSize: 12),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: ink),
  );
}

/// Opens the last board you were working on, otherwise the board list.
class LocalBoardApp extends StatefulWidget {
  const LocalBoardApp({super.key, required this.store, this.openBoardId});

  final BoardStore store;
  final String? openBoardId;

  @override
  State<LocalBoardApp> createState() => _LocalBoardAppState();
}

class _LocalBoardAppState extends State<LocalBoardApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    final id = widget.openBoardId ?? await widget.store.lastOpenedId();
    if (id == null || !mounted) return;
    try {
      final loaded = await widget.store.open(id);
      _navigator.currentState?.push(EditorScreen.route(widget.store, loaded));
    } on Object {
      await widget.store.setLastOpened(null); // board is gone: stay on the list
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Local Board',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(store: widget.store),
    );
  }
}
