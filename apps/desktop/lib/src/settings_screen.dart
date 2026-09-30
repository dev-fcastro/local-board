import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_board_canvas/local_board_canvas.dart';
import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

import 'app.dart' show appVersion;
import 'component_library.dart';
import 'services.dart';
import 'updater.dart';
import 'widgets.dart';

const _line = Color(0x3817181A);
const _muted = TextStyle(fontSize: 13, color: Color(Palette.inkSecondary), height: 1.4);

enum SettingsSection {
  updates('Updates', Icons.system_update_alt),
  storage('Cloud storage', Icons.cloud_outlined),
  plugins('Plugins', Icons.extension_outlined),
  about('About', Icons.info_outline);

  const SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initial = SettingsSection.updates});

  final SettingsSection initial;

  static Route<void> route([SettingsSection initial = SettingsSection.updates]) =>
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: initial));

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section = widget.initial;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 240,
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: _line))),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back (Esc)',
                          icon: const Icon(Icons.arrow_back, size: 20),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text(
                            'Settings',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    for (final s in SettingsSection.values)
                      _NavItem(section: s, selected: s == _section, onTap: () => setState(() => _section = s)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(48, 36, 48, 48),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: switch (_section) {
                        SettingsSection.updates => const _UpdatesSection(),
                        SettingsSection.storage => const _StorageSection(),
                        SettingsSection.plugins => const _PluginsSection(),
                        SettingsSection.about => const _AboutSection(),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, required this.onTap});

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(Palette.accent) : const Color(Palette.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0x144F46E5) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(section.icon, size: 18, color: color),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  section.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
        const SizedBox(height: 6),
        Text(subtitle, style: _muted.copyWith(fontSize: 14)),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(18), this.highlight});

  final Widget child;
  final EdgeInsets padding;
  final Color? highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: highlight ?? _line),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Updates

class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection();

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final release = s.availableUpdate;
    final automatic = s.updater?.kind.automatic ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Updates', 'Local Board looks for new versions on GitHub. Nothing else is sent.'),
        _Card(
          child: Row(
            children: [
              const AppLogo(size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Local Board $appVersion', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(switch (s.updateState) {
                      UpdateState.checking => 'Checking for updates…',
                      UpdateState.upToDate => 'You have the latest version.',
                      UpdateState.available => 'Version ${release!.version} is available.',
                      UpdateState.installing => 'Installing ${release!.version}…',
                      UpdateState.failed => s.updateError ?? 'Something went wrong.',
                      UpdateState.idle => 'Running on $platformName.',
                    }, style: _muted),
                  ],
                ),
              ),
              if (s.updateState == UpdateState.checking)
                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else if (s.updateState != UpdateState.installing)
                PillButton(
                  label: 'Check now',
                  icon: Icons.refresh,
                  onPressed: s.updater == null ? null : () => s.checkForUpdates(manual: true),
                ),
            ],
          ),
        ),
        if (release != null && (s.updateState == UpdateState.available || s.updateState == UpdateState.installing || s.updateState == UpdateState.failed))
          UpdateCard(services: s, release: release, automatic: automatic),
        _Card(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check for updates automatically'),
            subtitle: const Text('When the app starts. You always decide when to install.', style: _muted),
            value: s.settings.checkForUpdates,
            onChanged: (v) => s.updateSettings(s.settings.copyWith(checkForUpdates: v)),
          ),
        ),
      ],
    );
  }
}

/// The new version, its notes and the install button.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.services, required this.release, required this.automatic});

  final AppServices services;
  final ReleaseInfo release;
  final bool automatic;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final installing = s.updateState == UpdateState.installing;
    // Release notes are Markdown; show them as plain lines.
    final notes = release.notes
        .split('\n')
        .map((l) => l.trim().replaceFirst(RegExp(r'^#+\s*'), '').replaceFirst(RegExp(r'^[-*]\s+'), '• '))
        .map((l) => l.replaceAll('**', '').replaceAll('`', ''))
        .where((l) => l.isNotEmpty)
        .take(12)
        .join('\n');
    return _Card(
      highlight: const Color(Palette.accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What’s new in ${release.version}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (notes.isNotEmpty) Text(notes, style: _muted, maxLines: 12, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          if (installing) ...[
            LinearProgressIndicator(value: s.updateProgress, minHeight: 4, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            const Text('Downloading and checking the new version. Local Board restarts when it is ready.', style: _muted),
          ] else
            Row(
              children: [
                if (automatic)
                  PillButton(label: 'Update and restart', icon: Icons.download, filled: true, onPressed: s.installUpdate)
                else
                  PillButton(
                    label: 'Copy download link',
                    icon: Icons.link,
                    filled: true,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: release.page));
                      showMessage(context, 'Link copied. Open it in your browser to download ${release.version}.');
                    },
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: s.skipUpdate, child: const Text('Skip this version')),
              ],
            ),
          if (!automatic && !installing) ...[
            const SizedBox(height: 8),
            const Text('This copy was not installed with the installer, so it cannot update itself.', style: _muted),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cloud storage

IconData providerIcon(CloudProvider p) => switch (p) {
  CloudProvider.googleDrive => Icons.add_to_drive,
  CloudProvider.oneDrive => Icons.cloud_outlined,
  CloudProvider.protonDrive => Icons.shield_outlined,
  CloudProvider.dropbox => Icons.inventory_2_outlined,
  CloudProvider.iCloudDrive => Icons.cloud_queue,
  CloudProvider.s3 => Icons.storage_outlined,
  CloudProvider.webdav => Icons.dns_outlined,
  CloudProvider.folder => Icons.folder_outlined,
};

String providerHint(CloudProvider p) => switch (p.kind) {
  CloudKind.folder when p == CloudProvider.folder => 'Any folder another app keeps in sync (Syncthing, rclone, a NAS…).',
  CloudKind.folder => 'Through the ${p.label} app on this computer.',
  CloudKind.s3 => 'AWS S3, Cloudflare R2, Backblaze B2, Wasabi, MinIO…',
  CloudKind.webdav => 'Nextcloud, ownCloud, pCloud, Koofr, Synology…',
};

class _StorageSection extends StatelessWidget {
  const _StorageSection();

  Future<void> _add(BuildContext context) async {
    final provider = await showDialog<CloudProvider>(context: context, builder: (_) => const _ProviderPicker());
    if (provider == null || !context.mounted) return;
    await _edit(context, CloudStorageConfig(id: newId(), provider: provider));
  }

  Future<void> _edit(BuildContext context, CloudStorageConfig config) async {
    final s = Services.read(context);
    final result = await showDialog<CloudStorageConfig>(
      context: context,
      builder: (_) => _StorageDialog(initial: config),
    );
    if (result == null) return;
    await s.updateSettings(s.settings.withStorage(result));
    await s.syncNow(only: result.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final storages = s.settings.storages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title(
          'Cloud storage',
          'Your boards always stay on this computer. Add a storage to keep a synced copy there and '
              'open the same boards on your other computers.',
        ),
        for (final st in storages)
          _StorageTile(
            config: st,
            syncing: s.syncing,
            onToggle: (v) => s.updateSettings(s.settings.withStorage(st.copyWith(enabled: v))),
            onSync: () => s.syncNow(only: st.id),
            onEdit: () => _edit(context, st),
            onRemove: () async {
              final ok = await confirm(
                context,
                title: 'Remove ${st.provider.label}?',
                message: 'Local Board stops syncing with it. Boards already there and on this computer are kept.',
                action: 'Remove',
              );
              if (ok) await s.updateSettings(s.settings.withoutStorage(st.id));
            },
          ),
        if (storages.isEmpty)
          const _Card(
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, color: Color(Palette.inkTertiary)),
                SizedBox(width: 12),
                Expanded(child: Text('No storage yet. Boards are only on this computer.', style: _muted)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        PillButton(label: 'Add storage', icon: Icons.add, filled: true, onPressed: () => _add(context)),
        const SizedBox(height: 28),
        const Text('How it works', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text(
          'Local Board keeps a “Local Board” folder in the storage, with one file per board. '
          'It syncs a few seconds after you stop editing and every few minutes. If a board changed '
          'on two computers, the newest edit wins and the other version stays in its local backup. '
          'Boards you delete go to the trash on every computer, never destroyed.',
          style: _muted,
        ),
      ],
    );
  }
}

class _StorageTile extends StatelessWidget {
  const _StorageTile({
    required this.config,
    required this.syncing,
    required this.onToggle,
    required this.onSync,
    required this.onEdit,
    required this.onRemove,
  });

  final CloudStorageConfig config;
  final bool syncing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSync;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final problem = config.problem;
    final error = config.lastError;
    final String status;
    if (!config.enabled) {
      status = 'Paused';
    } else if (problem != null) {
      status = problem;
    } else if (syncing) {
      status = 'Syncing…';
    } else if (error != null) {
      status = error;
    } else if (config.lastSync != null) {
      status = 'Synced ${relativeTime(config.lastSync!)}';
    } else {
      status = 'Not synced yet';
    }
    final bad = config.enabled && (problem != null || (error != null && !syncing));
    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
      child: Row(
        children: [
          Icon(providerIcon(config.provider), color: const Color(Palette.accent)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.provider.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (config.summary.isNotEmpty)
                  Text(config.summary, style: _muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _muted.copyWith(fontSize: 12, color: bad ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
                ),
              ],
            ),
          ),
          Switch(value: config.enabled, onChanged: onToggle),
          PopupMenuButton<String>(
            tooltip: 'Storage actions',
            icon: const Icon(Icons.more_horiz, size: 18),
            onSelected: (v) => switch (v) {
              'sync' => onSync(),
              'edit' => onEdit(),
              'remove' => onRemove(),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'sync', enabled: config.enabled && problem == null, child: const Text('Sync now')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  const _ProviderPicker();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add storage'),
      content: SizedBox(
        width: 560,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          childAspectRatio: 3.2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in CloudProvider.values)
              InkWell(
                onTap: () => Navigator.of(context).pop(p),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(providerIcon(p), color: const Color(Palette.accent)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              providerHint(p),
                              style: _muted.copyWith(fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

class _StorageDialog extends StatefulWidget {
  const _StorageDialog({required this.initial});

  final CloudStorageConfig initial;

  @override
  State<_StorageDialog> createState() => _StorageDialogState();
}

class _StorageDialogState extends State<_StorageDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final key in _keys) key: TextEditingController(text: widget.initial.value(key)),
  };
  late final List<String> _detected = suggestedFolders(widget.initial.provider);
  bool _testing = false;
  String? _result;
  bool _ok = false;

  CloudProvider get provider => widget.initial.provider;

  List<String> get _keys => switch (provider.kind) {
    CloudKind.folder => const ['folder'],
    CloudKind.s3 => const ['endpoint', 'region', 'bucket', 'prefix', 'accessKeyId', 'secretAccessKey'],
    CloudKind.webdav => const ['url', 'username', 'password'],
  };

  CloudStorageConfig get _config => widget.initial.copyWith(
    values: {
      for (final e in _fields.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    },
    lastError: () => null,
  );

  @override
  void initState() {
    super.initState();
    if (provider.kind == CloudKind.folder && _fields['folder']!.text.isEmpty && _detected.isNotEmpty) {
      _fields['folder']!.text = _detected.first;
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _test() async {
    final config = _config;
    final problem = config.problem;
    if (problem != null) {
      setState(() {
        _result = problem;
        _ok = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      await testRemoteStore(remoteStoreFor(config));
      _result = 'Connected. Local Board can read and write there.';
      _ok = true;
    } on Object catch (e) {
      _result = '$e';
      _ok = false;
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (dir != null) setState(() => _fields['folder']!.text = dir);
  }

  Widget _field(String key, String label, {String? hint, bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _fields[key],
      obscureText: secret,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final List<Widget> body = switch (provider.kind) {
      CloudKind.folder => [
        Text(
          provider == CloudProvider.folder
              ? 'Choose a folder that another app keeps in sync. Local Board creates a “Local Board” folder inside it.'
              : 'Local Board saves into the folder the ${provider.label} app keeps in sync, so it works offline and '
                    'needs no password here. It creates a “Local Board” folder inside it.',
          style: _muted,
        ),
        const SizedBox(height: 14),
        if (_detected.length > 1)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in _detected)
                ChoiceChip(
                  label: Text(d, style: const TextStyle(fontSize: 12)),
                  selected: _fields['folder']!.text == d,
                  onSelected: (_) => setState(() => _fields['folder']!.text = d),
                ),
            ],
          ),
        if (_detected.isEmpty && provider != CloudProvider.folder)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'No ${provider.label} folder found on this computer. Install the ${provider.label} app and sign in, '
              'or choose the folder where it syncs.',
              style: _muted.copyWith(color: const Color(0xFFB45309)),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field('folder', 'Folder')),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PillButton(label: 'Choose…', icon: Icons.folder_open, onPressed: _pickFolder),
            ),
          ],
        ),
      ],
      CloudKind.s3 => [
        const Text(
          'Works with any S3-compatible service. Use a key that can only access this bucket.',
          style: _muted,
        ),
        const SizedBox(height: 14),
        _field('endpoint', 'Endpoint (leave empty for AWS)', hint: 'https://<account>.r2.cloudflarestorage.com'),
        Row(
          children: [
            Expanded(child: _field('bucket', 'Bucket')),
            const SizedBox(width: 10),
            SizedBox(width: 170, child: _field('region', 'Region', hint: 'us-east-1 · auto')),
          ],
        ),
        _field('prefix', 'Folder in the bucket (optional)'),
        _field('accessKeyId', 'Access key ID'),
        _field('secretAccessKey', 'Secret access key', secret: true),
      ],
      CloudKind.webdav => [
        const Text('Use an app password if your server offers them.', style: _muted),
        const SizedBox(height: 14),
        _field('url', 'Server address', hint: 'https://cloud.example.com/remote.php/dav/files/you/'),
        _field('username', 'User name'),
        _field('password', 'Password', secret: true),
      ],
    };

    return AlertDialog(
      title: Row(
        children: [
          Icon(providerIcon(provider), color: const Color(Palette.accent)),
          const SizedBox(width: 10),
          Text(provider.label),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...body,
              if (provider.kind != CloudKind.folder)
                const Text(
                  'Credentials are saved in the settings file on this computer, readable only by your user.',
                  style: TextStyle(fontSize: 11, color: Color(Palette.inkTertiary)),
                ),
              if (_testing || _result != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_testing)
                      const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(
                        _ok ? Icons.check_circle : Icons.error_outline,
                        size: 18,
                        color: _ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_testing ? 'Testing…' : _result!, style: _muted)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _testing ? null : _test, child: const Text('Test connection')),
        FilledButton(
          onPressed: () {
            final config = _config;
            if (config.problem != null) {
              setState(() {
                _result = config.problem;
                _ok = false;
              });
              return;
            }
            Navigator.of(context).pop(config);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Plugins

class _PluginsSection extends StatelessWidget {
  const _PluginsSection();

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title(
          'Plugins',
          'Plugins add ready-made components for a kind of diagram. Turning one off only hides it from the '
              'component library; boards that use it keep showing its components.',
        ),
        for (final p in builtInPlugins)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Color(p.color).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ComponentIconView(icon: p.kinds.firstWhere((k) => k.id == 'service' || k.id == 'router', orElse: () => p.kinds.first).icon, color: Color(p.color)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${p.kinds.length} components · version ${p.version} · built in', style: _muted.copyWith(fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: s.settings.isPluginEnabled(p.id),
                      onChanged: (v) => s.updateSettings(s.settings.withPlugin(p.id, enabled: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(p.description, style: _muted),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in p.kinds)
                      Tooltip(
                        message: k.label,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(6)),
                          child: ComponentIconView(icon: k.icon, color: Color(p.color), size: 20),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// About

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('About', 'A local-first whiteboard. Your boards live on your computer.'),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row('Version', '$appVersion · $platformName'),
              _Row('Boards folder', s.store.boardsDir.path),
              _Row('Settings file', s.settingsStore.file.path),
              const _Row('Source code', 'github.com/$releasesRepo'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 140, child: Text(label, style: _muted)),
        Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
