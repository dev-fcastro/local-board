import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

import 'component_library.dart';
import 'image_input.dart';
import 'layers_panel.dart';
import 'services.dart';
import 'settings_screen.dart';
import 'toolbar.dart';
import 'widgets.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.store, required this.loaded});

  final BoardStore store;
  final LoadedBoard loaded;

  static Route<void> route(BoardStore store, LoadedBoard loaded) => PageRouteBuilder(
    pageBuilder: (_, _, _) => EditorScreen(store: store, loaded: loaded),
    transitionDuration: const Duration(milliseconds: 120),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late final BoardController c = BoardController(widget.loaded.document);
  late final Autosaver saver = Autosaver(
    document: c.document,
    save: widget.store.save,
    onStatus: (status, _) {
      if (status == SaveStatus.saved) _services?.scheduleSync();
      if (mounted) setState(() {});
    },
  );
  AppServices? _services;
  bool _library = false;
  bool _layers = false;
  bool _dropping = false;
  final _canvasFocus = FocusNode(debugLabel: 'board');
  late final AppLifecycleListener _lifecycle;

  BoardStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.clipboardReader = readSystemClipboard; // Ctrl+V also sees images and copied files
    store.setLastOpened(c.document.id);
    // Flush before the process goes away (window close, logout).
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await saver.flush();
        return AppExitResponse.exit;
      },
      onHide: saver.flush,
      onPause: saver.flush,
    );
    if (widget.loaded.wasRecovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showMessage(context, 'Recovered this board from its ${widget.loaded.recoveredFrom}. Nothing was lost.');
        saver.markDirty();
        unawaited(store.save(c.document));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= Services.read(context)
      ..openBoards.add(c.document.id)
      ..registerFlusher(saver.flush);
  }

  void _onChange() {
    saver.markDirty();
    setState(() {});
  }

  @override
  void dispose() {
    _services
      ?..openBoards.remove(c.document.id)
      ..unregisterFlusher(saver.flush)
      ..scheduleSync();
    c.removeListener(_onChange);
    _lifecycle.dispose();
    unawaited(saver.dispose());
    c.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  Future<void> _back() async {
    await saver.flush();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _rename() async {
    final t = await promptText(context, title: 'Rename board', initial: c.document.title);
    if (t != null) c.rename(t);
    _canvasFocus.requestFocus();
  }

  String get _safeName {
    final n = c.document.title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
    return n.isEmpty ? 'board' : n;
  }

  Future<void> _export(String kind) async {
    if (c.document.isEmpty && kind != 'whiteboard') {
      showMessage(context, 'Nothing to export yet — draw something first.');
      return;
    }
    final (label, ext) = switch (kind) {
      'png' => ('PNG image', 'png'),
      'svg' => ('SVG image', 'svg'),
      _ => ('Local Board file', 'whiteboard'),
    };
    final location = await getSaveLocation(
      suggestedName: '$_safeName.$ext',
      acceptedTypeGroups: [XTypeGroup(label: label, extensions: [ext])],
    );
    if (location == null) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
    try {
      switch (kind) {
        case 'png':
          await File(path).writeAsBytes(await exportPng(c.document), flush: true);
        case 'svg':
          await File(path).writeAsString(exportSvg(c.document), flush: true);
        default:
          await saver.flush();
          await store.exportTo(c.document, path);
      }
      if (mounted) showMessage(context, 'Exported to $path');
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Export failed: $e');
    }
    _canvasFocus.requestFocus();
  }

  Future<void> _managePlugins() async {
    await saver.flush();
    if (!mounted) return;
    await Navigator.of(context).push(SettingsScreen.route(SettingsSection.plugins));
    _canvasFocus.requestFocus();
  }

  void _toggleLibrary() {
    setState(() => _library = !(_library || c.tool == Tool.component));
    if (!_library && c.tool == Tool.component) c.setTool(Tool.select);
    _canvasFocus.requestFocus();
  }

  void _toggleLayers() {
    setState(() => _layers = !_layers);
    _canvasFocus.requestFocus();
  }

  /// "Insert image": pick picture files and put them in the middle of the view.
  Future<void> _insertImage() async {
    final picked = await pickImages();
    if (!mounted) return;
    if (picked.isNotEmpty) await _addImages(picked);
    _canvasFocus.requestFocus();
  }

  Future<void> _addImages(List<PastedImage> images, {Vec2? at}) async {
    var added = 0;
    for (final image in images) {
      final shift = const Vec2(24, 24) * added.toDouble();
      if (await c.insertImage(image.bytes, name: image.name, center: at, shift: shift)) added++;
    }
    if (mounted && added < images.length) {
      showMessage(
        context,
        added == 0 ? 'That file is not a picture Local Board can open.' : 'Some files were not pictures and were skipped.',
      );
    }
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dropping = false);
    final images = await readImageFiles(details.files.map((f) => f.path));
    if (!mounted) return;
    if (images.isEmpty) {
      showMessage(context, 'Drop PNG, JPG, GIF, WebP or BMP pictures here.');
      return;
    }
    await _addImages(images, at: c.toWorld(details.localPosition));
    _canvasFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final showLibrary = _library || c.tool == Tool.component;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          saver.flush();
          showMessage(context, 'Saved. Local Board also saves automatically as you work.');
        },
        const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true): () => _export('png'),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): _back,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true): _toggleLayers,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true): _insertImage,
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: DropTarget(
                onDragEntered: (_) => setState(() => _dropping = true),
                onDragExited: (_) => setState(() => _dropping = false),
                onDragDone: _onDrop,
                child: BoardCanvas(controller: c, focusNode: _canvasFocus),
              ),
            ),
            if (_dropping)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0x0F4F46E5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(Palette.accent), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Drop pictures to add them to the board',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(Palette.accent)),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: _TopBar(
                title: c.document.title,
                status: saver.status,
                onBack: _back,
                onRename: _rename,
                onExport: _export,
                layersOpen: _layers,
                onLayers: _toggleLayers,
                canUndo: c.canUndo,
                canRedo: c.canRedo,
                onUndo: c.undo,
                onRedo: c.redo,
                cloud: services.cloudEnabled,
                update: services.showUpdateBanner ? services.availableUpdate?.version : null,
                onUpdate: () => Navigator.of(context).push(SettingsScreen.route()),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(child: ToolDock(
                  controller: c,
                  libraryOpen: showLibrary,
                  onLibrary: _toggleLibrary,
                  onInsertImage: _insertImage,
                )),
            ),
            Positioned(left: 12, top: 72, child: StylePanel(controller: c)),
            if (showLibrary)
              Positioned(
                right: 12,
                top: 72,
                bottom: 72,
                child: Align(
                  alignment: Alignment.topRight,
                  child: ComponentLibrary(
                    controller: c,
                    plugins: services.enabledPlugins,
                    onClose: _toggleLibrary,
                    onManage: _managePlugins,
                  ),
                ),
              ),
            if (_layers)
              Positioned(
                // Next to the component library when both are open.
                right: showLibrary ? 12 + 248 + 20 + 8 : 12,
                top: 72,
                bottom: 72,
                child: Align(
                  alignment: Alignment.topRight,
                  child: LayersPanel(controller: c, onClose: _toggleLayers),
                ),
              ),
            Positioned(right: 12, bottom: 16, child: ZoomControls(controller: c)),
            if (c.document.isEmpty && c.editing == null && !c.isInteracting)
              const Positioned.fill(child: IgnorePointer(child: _EmptyHint())),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.status,
    required this.onBack,
    required this.onRename,
    required this.onExport,
    required this.layersOpen,
    required this.onLayers,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.cloud,
    required this.onUpdate,
    this.update,
  });

  final String title;
  final SaveStatus status;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final void Function(String) onExport;
  final bool layersOpen;
  final VoidCallback onLayers;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool cloud;

  /// Version of an available update, if any.
  final String? update;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Panel(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBtn(icon: Icons.arrow_back, tooltip: 'All boards (Ctrl+W)', onPressed: onBack),
              const SizedBox(width: 4),
              const AppLogo(size: 20),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Rename',
                child: InkWell(
                  onTap: onRename,
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SaveIndicator(status: status, cloud: cloud),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const Spacer(),
        if (update != null) ...[
          Panel(
            child: InkWell(
              onTap: onUpdate,
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.new_releases_outlined, size: 18, color: Color(Palette.accent)),
                    const SizedBox(width: 6),
                    Text(
                      'Update to $update',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(Palette.accent)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Panel(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBtn(icon: Icons.undo, tooltip: 'Undo (Ctrl+Z)', onPressed: canUndo ? onUndo : null),
              IconBtn(icon: Icons.redo, tooltip: 'Redo (Ctrl+Shift+Z)', onPressed: canRedo ? onRedo : null),
              const VerticalDivider(width: 12, indent: 8, endIndent: 8),
              IconBtn(icon: Icons.layers_outlined, tooltip: 'Layers (Ctrl+Shift+L)', active: layersOpen, onPressed: onLayers),
              PopupMenuButton<String>(
                tooltip: 'Export',
                onSelected: onExport,
                position: PopupMenuPosition.under,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'png', child: Text('Export as PNG…   Ctrl+Shift+E')),
                  PopupMenuItem(value: 'svg', child: Text('Export as SVG…')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'whiteboard', child: Text('Save a copy (.whiteboard)…')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.ios_share, size: 18),
                      SizedBox(width: 6),
                      Text('Export', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Color(Palette.inkTertiary), fontSize: 14);
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pick a tool below and start drawing.', style: TextStyle(color: Color(Palette.inkSecondary), fontSize: 18)),
          SizedBox(height: 8),
          Text(
            'P pen · R rectangle · T text · N sticky note · C components · Ctrl+V paste an image · drop pictures here · Space+drag to move around · wheel to zoom',
            style: style,
          ),
        ],
      ),
    );
  }
}
