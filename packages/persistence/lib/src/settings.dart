import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cloud/cloud_config.dart';

/// App-wide preferences, stored as `settings.json` next to the boards.
final class AppSettings {
  const AppSettings({
    this.disabledPlugins = const {},
    this.checkForUpdates = true,
    this.skippedVersion,
    this.storages = const [],
  });

  /// Plugins hidden from the component library. Boards that already use them
  /// still show their components.
  final Set<String> disabledPlugins;

  /// Look for a new version on startup.
  final bool checkForUpdates;

  /// Version the user chose not to be reminded about.
  final String? skippedVersion;

  /// Cloud storages boards are synced to.
  final List<CloudStorageConfig> storages;

  bool isPluginEnabled(String id) => !disabledPlugins.contains(id);

  AppSettings copyWith({
    Set<String>? disabledPlugins,
    bool? checkForUpdates,
    String? Function()? skippedVersion,
    List<CloudStorageConfig>? storages,
  }) => AppSettings(
    disabledPlugins: disabledPlugins ?? this.disabledPlugins,
    checkForUpdates: checkForUpdates ?? this.checkForUpdates,
    skippedVersion: skippedVersion != null ? skippedVersion() : this.skippedVersion,
    storages: storages ?? this.storages,
  );

  AppSettings withPlugin(String id, {required bool enabled}) =>
      copyWith(disabledPlugins: enabled ? ({...disabledPlugins}..remove(id)) : {...disabledPlugins, id});

  /// Replaces the storage with the same id, or adds it.
  AppSettings withStorage(CloudStorageConfig s) {
    final i = storages.indexWhere((e) => e.id == s.id);
    return copyWith(storages: i < 0 ? [...storages, s] : ([...storages]..[i] = s));
  }

  AppSettings withoutStorage(String id) => copyWith(storages: [...storages.where((e) => e.id != id)]);

  Map<String, Object?> toJson() => {
    'disabledPlugins': disabledPlugins.toList()..sort(),
    'checkForUpdates': checkForUpdates,
    if (skippedVersion != null) 'skippedVersion': skippedVersion,
    'storages': [for (final s in storages) s.toJson()],
  };

  /// Lenient: an unreadable field falls back to its default instead of
  /// losing every other preference.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    final disabled = json['disabledPlugins'];
    final storages = json['storages'];
    return AppSettings(
      disabledPlugins: {if (disabled is List) ...disabled.whereType<String>()},
      checkForUpdates: json['checkForUpdates'] is bool ? json['checkForUpdates'] as bool : true,
      skippedVersion: json['skippedVersion'] is String ? json['skippedVersion'] as String : null,
      storages: [
        if (storages is List)
          for (final s in storages) ?CloudStorageConfig.tryParse(s),
      ],
    );
  }
}

final class SettingsStore {
  SettingsStore(this.root);

  final Directory root;

  File get file => File(p.join(root.path, 'settings.json'));

  Future<AppSettings> load() async {
    try {
      return AppSettings.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return const AppSettings();
    }
  }

  /// Atomic (tmp + rename) and, on Linux and macOS, readable only by the
  /// user, since it can hold cloud credentials.
  Future<void> save(AppSettings settings) async {
    await root.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(settings.toJson()), flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmp.path]);
      } on Object {
        // Best effort.
      }
    }
    await tmp.rename(file.path);
  }
}
