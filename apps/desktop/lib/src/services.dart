import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:local_board_core/local_board_core.dart';
import 'package:local_board_persistence/local_board_persistence.dart';

import 'updater.dart';

enum UpdateState { idle, checking, upToDate, available, installing, failed }

/// App-wide state shared by every screen: settings, cloud sync and updates.
class AppServices extends ChangeNotifier {
  AppServices({
    required this.store,
    required this.settingsStore,
    AppSettings settings = const AppSettings(),
    this.updater,
  }) : _settings = settings;

  /// Loads the saved settings for [store].
  static Future<AppServices> load(BoardStore store, {Updater? updater}) async {
    final settingsStore = SettingsStore(store.root);
    return AppServices(
      store: store,
      settingsStore: settingsStore,
      settings: await settingsStore.load(),
      updater: updater,
    );
  }

  final BoardStore store;
  final SettingsStore settingsStore;

  /// Null in tests, so nothing reaches the network.
  final Updater? updater;

  AppSettings get settings => _settings;
  AppSettings _settings;

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    notifyListeners();
    await settingsStore.save(s);
  }

  /// Plugins shown in the component library.
  List<BoardPlugin> get enabledPlugins => [
    for (final p in builtInPlugins)
      if (_settings.isPluginEnabled(p.id)) p,
  ];

  Timer? _periodic;

  /// Background work after the first frame: check for updates and sync.
  void start() {
    if (_settings.checkForUpdates) unawaited(checkForUpdates());
    unawaited(syncNow());
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  // ---- open editors ----

  /// Boards open in an editor: sync never replaces them underneath the user.
  final Set<String> openBoards = {};

  /// Saves pending edits; run before the app quits to update.
  final Set<Future<void> Function()> _flushers = {};

  void registerFlusher(Future<void> Function() f) => _flushers.add(f);
  void unregisterFlusher(Future<void> Function() f) => _flushers.remove(f);

  // ---- cloud sync ----

  bool get syncing => _syncing;
  bool _syncing = false;
  bool _syncAgain = false;
  Timer? _syncTimer;

  /// Bumped whenever a sync changed boards on this computer.
  final ValueNotifier<int> boardsChanged = ValueNotifier(0);

  List<CloudStorageConfig> get activeStorages => [
    for (final s in _settings.storages)
      if (s.enabled && s.problem == null) s,
  ];

  bool get cloudEnabled => activeStorages.isNotEmpty;

  /// Call after a save: syncs a few seconds after editing pauses.
  void scheduleSync() {
    if (!cloudEnabled) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 5), syncNow);
  }

  /// Syncs every active storage (or only [only]). Errors are kept on the
  /// storage and shown in Settings; boards on this computer are never lost.
  Future<void> syncNow({String? only}) async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    final targets = [
      for (final s in activeStorages)
        if (only == null || s.id == only) s,
    ];
    if (targets.isEmpty) return;
    _syncing = true;
    notifyListeners();
    var changed = false;
    try {
      for (final target in targets) {
        CloudStorageConfig result;
        try {
          final report = await syncBoards(store, remoteStoreFor(target), busy: {...openBoards});
          changed |= report.changedLocal;
          result = target.copyWith(lastSync: DateTime.now, lastError: () => null);
        } on Object catch (e) {
          result = target.copyWith(lastError: () => '$e');
        }
        // Re-read: the user may have edited settings while this ran.
        final current = _settings.storages.where((s) => s.id == target.id).firstOrNull;
        if (current != null) {
          _settings = _settings.withStorage(current.copyWith(lastSync: () => result.lastSync, lastError: () => result.lastError));
        }
      }
      await settingsStore.save(_settings);
    } finally {
      _syncing = false;
      if (changed) boardsChanged.value++;
      notifyListeners();
    }
    if (_syncAgain) {
      _syncAgain = false;
      await syncNow();
    }
  }

  // ---- updates ----

  UpdateState get updateState => _updateState;
  UpdateState _updateState = UpdateState.idle;
  ReleaseInfo? get availableUpdate => _available;
  ReleaseInfo? _available;
  String? get updateError => _updateError;
  String? _updateError;
  double? get updateProgress => _progress;
  double? _progress;

  /// Whether to show the "new version" banner.
  bool get showUpdateBanner =>
      _updateState == UpdateState.available && _available?.version != _settings.skippedVersion ||
      _updateState == UpdateState.installing;

  Future<void> checkForUpdates({bool manual = false}) async {
    final u = updater;
    if (u == null || _updateState == UpdateState.checking || _updateState == UpdateState.installing) return;
    _updateState = UpdateState.checking;
    _updateError = null;
    notifyListeners();
    try {
      _available = await u.check();
      _updateState = _available == null ? UpdateState.upToDate : UpdateState.available;
      if (manual && _available != null && _settings.skippedVersion == _available!.version) {
        await updateSettings(_settings.copyWith(skippedVersion: () => null));
      }
    } on Object catch (e) {
      _updateState = manual ? UpdateState.failed : UpdateState.idle;
      _updateError = e is UpdateException ? e.message : 'Could not reach GitHub. Check your connection.';
    }
    notifyListeners();
  }

  Future<void> skipUpdate() async {
    final v = _available?.version;
    if (v != null) await updateSettings(_settings.copyWith(skippedVersion: () => v));
  }

  /// Downloads, verifies and installs the update, then restarts the app.
  Future<void> installUpdate() async {
    final u = updater, release = _available;
    if (u == null || release == null || _updateState == UpdateState.installing) return;
    _updateState = UpdateState.installing;
    _progress = 0;
    _updateError = null;
    notifyListeners();
    try {
      for (final flush in [..._flushers]) {
        await flush();
      }
      await syncNow();
      final program = await u.prepare(
        release,
        onProgress: (v) {
          _progress = v;
          notifyListeners();
        },
      );
      await Updater.relaunch(program);
    } on Object catch (e) {
      _updateState = UpdateState.failed;
      _updateError = e is UpdateException ? e.message : 'The update could not be installed: $e';
      notifyListeners();
    }
  }
}

/// Makes [AppServices] available to every screen.
class Services extends InheritedNotifier<AppServices> {
  const Services({super.key, required AppServices services, required super.child}) : super(notifier: services);

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Services>()!.notifier!;

  /// Without rebuilding when services change.
  static AppServices read(BuildContext context) => context.getInheritedWidgetOfExactType<Services>()!.notifier!;
}
