import 'package:flutter/material.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';

import 'toolbar.dart';

/// A plugin component icon at any size.
class ComponentIconView extends StatelessWidget {
  const ComponentIconView({super.key, required this.icon, required this.color, this.size = 24});

  final ComponentIcon icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _IconPainter(icon, color)));
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final ComponentIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintComponentIcon(canvas, icon, Offset.zero & size, color);

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color;
}

/// Side panel listing the components of every enabled plugin. Click one,
/// then click the board to place it.
class ComponentLibrary extends StatefulWidget {
  const ComponentLibrary({
    super.key,
    required this.controller,
    required this.plugins,
    required this.onClose,
    required this.onManage,
  });

  final BoardController controller;
  final List<BoardPlugin> plugins;
  final VoidCallback onClose;
  final VoidCallback onManage;

  @override
  State<ComponentLibrary> createState() => _ComponentLibraryState();
}

class _ComponentLibraryState extends State<ComponentLibrary> {
  final _search = TextEditingController();
  String? _pluginId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final plugins = widget.plugins;
    final query = _search.text.trim().toLowerCase();
    final current = plugins.where((p) => p.id == _pluginId).firstOrNull ?? plugins.firstOrNull;

    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: SizedBox(
        width: 248,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Components', style: TextStyle(fontWeight: FontWeight.w600))),
                IconBtn(icon: Icons.tune, tooltip: 'Manage plugins', onPressed: widget.onManage),
                IconBtn(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
              ],
            ),
            if (plugins.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Every plugin is turned off.',
                      style: TextStyle(color: Color(Palette.inkSecondary), fontSize: 13),
                    ),
                    TextButton(onPressed: widget.onManage, child: const Text('Turn plugins on')),
                  ],
                ),
              )
            else ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search components',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              if (query.isEmpty && plugins.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in plugins)
                      _PluginChip(plugin: p, selected: p == current, onTap: () => setState(() => _pluginId = p.id)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 4),
                  child: query.isEmpty
                      ? _grid(c, current!, current.kinds)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final p in plugins)
                              if (p.kinds.where((k) => k.label.toLowerCase().contains(query)).toList() case final kinds
                                  when kinds.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                                  child: Text(
                                    p.name.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, letterSpacing: 0.8, color: Color(Palette.inkSecondary)),
                                  ),
                                ),
                                _grid(c, p, kinds),
                              ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Click a component, then click the board. Double-click it to rename.',
                style: TextStyle(fontSize: 11, color: Color(Palette.inkTertiary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _grid(BoardController c, BoardPlugin plugin, List<ComponentKind> kinds) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 0.92,
      children: [
        for (final k in kinds)
          _Tile(
            plugin: plugin,
            kind: k,
            active: c.tool == Tool.component && c.armedKind == k,
            onTap: () => c.armComponent(plugin, k),
          ),
      ],
    );
  }
}

class _PluginChip extends StatelessWidget {
  const _PluginChip({required this.plugin, required this.selected, required this.onTap});

  final BoardPlugin plugin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(plugin.color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : null,
          border: Border.all(color: selected ? color : const Color(0x3817181A)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          plugin.name.replaceAll(' architecture', ''),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? color : const Color(Palette.ink)),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.plugin, required this.kind, required this.active, required this.onTap});

  final BoardPlugin plugin;
  final ComponentKind kind;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(plugin.color);
    return Tooltip(
      message: kind.body == ComponentBody.zone ? '${kind.label} (frames other components)' : kind.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.1) : null,
            border: Border.all(color: active ? color : const Color(0x2217181A)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ComponentIconView(icon: kind.icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                kind.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
