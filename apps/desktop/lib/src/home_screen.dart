import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

import 'app.dart' show appVersion;
import 'editor_screen.dart';
import 'services.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// "Your boards": every board on this computer, newest first.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final BoardStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<BoardSummary>? _boards;

  BoardStore get store => widget.store;
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Services.read(context);
    if (s != _services) {
      _services?.boardsChanged.removeListener(_reload);
      _services = s..boardsChanged.addListener(_reload);
    }
  }

  @override
  void dispose() {
    _services?.boardsChanged.removeListener(_reload);
    super.dispose();
  }

  Future<void> _settings([SettingsSection section = SettingsSection.updates]) async {
    await Navigator.of(context).push(SettingsScreen.route(section));
    await _reload();
  }

  Future<void> _reload() async {
    final list = await store.list();
    if (mounted) setState(() => _boards = list);
  }

  Future<void> _open(String id) async {
    try {
      final loaded = await store.open(id);
      if (!mounted) return;
      await Navigator.of(context).push(EditorScreen.route(store, loaded));
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not open this board: $e');
    }
    await store.setLastOpened(null);
    await _reload();
    _services?.scheduleSync();
  }

  Future<void> _create() async {
    final doc = await store.create();
    await _open(doc.id);
  }

  Future<void> _import() async {
    const type = XTypeGroup(label: 'Local Board', extensions: ['whiteboard']);
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null) return;
    try {
      final doc = await store.importFrom(file.path);
      await _open(doc.id);
    } on Object catch (e) {
      if (mounted) showMessage(context, 'That file could not be imported: $e');
    }
  }

  Future<void> _rename(BoardSummary b) async {
    final title = await promptText(context, title: 'Rename board', initial: b.title);
    if (title == null || title.trim().isEmpty) return;
    final loaded = await store.open(b.id);
    loaded.document.rename(title.trim());
    await store.save(loaded.document);
    await _reload();
  }

  Future<void> _duplicate(BoardSummary b) async {
    await store.duplicate(b.id);
    await _reload();
  }

  Future<void> _delete(BoardSummary b) async {
    final ok = await confirm(
      context,
      title: 'Delete “${b.title}”?',
      message: 'It will be moved to the trash folder inside your Local Board data directory.',
      action: 'Delete',
    );
    if (!ok) return;
    await store.moveToTrash(b.id);
    await _reload();
    _services?.scheduleSync();
  }

  @override
  Widget build(BuildContext context) {
    final boards = _boards;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _create,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _import,
        const SingleActivator(LogicalKeyboardKey.comma, control: true): _settings,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onNew: _create, onImport: _import, onSettings: _settings),
              const Divider(),
              UpdateBanner(onDetails: () => _settings(SettingsSection.updates)),
              Expanded(
                child: boards == null
                    ? const SizedBox.shrink()
                    : boards.isEmpty
                    ? _Empty(onNew: _create)
                    : _Grid(
                        store: store,
                        boards: boards,
                        onOpen: (b) => _open(b.id),
                        onRename: _rename,
                        onDuplicate: _duplicate,
                        onDelete: _delete,
                      ),
              ),
              _Footer(path: store.root.path, onCloud: () => _settings(SettingsSection.storage)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNew, required this.onImport, required this.onSettings});

  final VoidCallback onNew;
  final VoidCallback onImport;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Row(
        children: [
          const AppLogo(size: 30),
          const SizedBox(width: 12),
          const Text('Local Board', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
          const Spacer(),
          IconButton(
            tooltip: 'Settings (Ctrl+,)',
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: onSettings,
          ),
          const SizedBox(width: 8),
          PillButton(label: 'Open file…', icon: Icons.file_open_outlined, onPressed: onImport, tooltip: 'Ctrl+O'),
          const SizedBox(width: 8),
          PillButton(label: 'New board', icon: Icons.add, onPressed: onNew, filled: true, tooltip: 'Ctrl+N'),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Your boards live here.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          const Text(
            'Saved on this computer as you draw. No account, no internet.',
            style: TextStyle(color: Color(Palette.inkSecondary)),
          ),
          const SizedBox(height: 24),
          PillButton(label: 'Create your first board', icon: Icons.add, onPressed: onNew, filled: true),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.store,
    required this.boards,
    required this.onOpen,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final BoardStore store;
  final List<BoardSummary> boards;
  final void Function(BoardSummary) onOpen;
  final void Function(BoardSummary) onRename;
  final void Function(BoardSummary) onDuplicate;
  final void Function(BoardSummary) onDelete;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 1.25,
      ),
      itemCount: boards.length,
      itemBuilder: (context, i) {
        final b = boards[i];
        return _BoardCard(
          store: store,
          board: b,
          onOpen: () => onOpen(b),
          onRename: () => onRename(b),
          onDuplicate: () => onDuplicate(b),
          onDelete: () => onDelete(b),
        );
      },
    );
  }
}

class _BoardCard extends StatefulWidget {
  const _BoardCard({
    required this.store,
    required this.board,
    required this.onOpen,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final BoardStore store;
  final BoardSummary board;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.board;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hover ? const Color(Palette.accent) : const Color(0x3817181A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: BoardThumbnail(store: widget.store, board: b),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '${relativeTime(b.updatedAt)} · ${b.objectCount} ${b.objectCount == 1 ? 'item' : 'items'}',
                            style: const TextStyle(fontSize: 12, color: Color(Palette.inkSecondary)),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Board actions',
                      icon: const Icon(Icons.more_horiz, size: 18),
                      onSelected: (v) => switch (v) {
                        'rename' => widget.onRename(),
                        'duplicate' => widget.onDuplicate(),
                        'delete' => widget.onDelete(),
                        _ => null,
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.path, required this.onCloud});

  final String path;
  final VoidCallback onCloud;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final storages = s.activeStorages;
    final where = storages.isEmpty
        ? 'Stored only on this computer'
        : 'Stored on this computer, synced to ${storages.map((e) => e.provider.label).join(', ')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x3817181A)))),
      child: Row(
        children: [
          Icon(
            storages.isEmpty ? Icons.lock_outline : Icons.cloud_done_outlined,
            size: 14,
            color: const Color(Palette.inkSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              '$where · $path',
              style: const TextStyle(fontSize: 12, color: Color(Palette.inkSecondary)),
            ),
          ),
          if (s.syncing)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Text('Syncing…', style: TextStyle(fontSize: 12, color: Color(Palette.inkSecondary))),
            ),
          if (storages.isEmpty)
            TextButton(
              onPressed: onCloud,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
              child: const Text('Add cloud storage'),
            ),
          const SizedBox(width: 8),
          Text(
            'v$appVersion · $platformName',
            style: const TextStyle(fontSize: 12, color: Color(Palette.inkTertiary)),
          ),
        ],
      ),
    );
  }
}

/// "A new version is available", shown until installed or skipped.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.onDetails});

  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final release = s.availableUpdate;
    if (!s.showUpdateBanner || release == null) return const SizedBox.shrink();
    final installing = s.updateState == UpdateState.installing;
    final automatic = s.updater?.kind.automatic ?? false;
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0x0F4F46E5),
        border: Border.all(color: const Color(Palette.accent)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.new_releases_outlined, color: Color(Palette.accent), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: installing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Installing Local Board ${release.version}…', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: s.updateProgress, minHeight: 3, borderRadius: BorderRadius.circular(3)),
                    ],
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Local Board ${release.version} is available. ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: automatic
                              ? 'Update now and the app restarts with your boards as they are.'
                              : 'See what is new and how to get it.',
                          style: const TextStyle(color: Color(Palette.inkSecondary)),
                        ),
                      ],
                    ),
                  ),
          ),
          if (!installing) ...[
            TextButton(onPressed: onDetails, child: const Text('What’s new')),
            TextButton(onPressed: s.skipUpdate, child: const Text('Later')),
            const SizedBox(width: 4),
            if (automatic) PillButton(label: 'Update', icon: Icons.download, filled: true, onPressed: s.installUpdate),
          ],
        ],
      ),
    );
  }
}
