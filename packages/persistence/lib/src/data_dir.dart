import 'dart:io';

import 'package:path/path.dart' as p;

/// Where boards live by default, following each OS's convention.
/// Linux: `$XDG_DATA_HOME/local-board` or `~/.local/share/local-board`.
Directory defaultDataDirectory({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final override = env['LOCAL_BOARD_DATA_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);

  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  if (Platform.isWindows) {
    return Directory(p.join(env['APPDATA'] ?? p.join(home, 'AppData', 'Roaming'), 'Local Board'));
  }
  if (Platform.isMacOS) {
    return Directory(p.join(home, 'Library', 'Application Support', 'Local Board'));
  }
  final xdg = env['XDG_DATA_HOME'];
  final base = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.local', 'share');
  return Directory(p.join(base, 'local-board'));
}
