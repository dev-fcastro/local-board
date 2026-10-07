/// Schema version written by this build.
const currentSchemaVersion = 3;

typedef Migration = Map<String, Object?> Function(Map<String, Object?> json);

/// `migrations[n]` upgrades a schema-n document to schema n+1.
/// Add an entry here — never edit an old one — when the format changes (plan §7).
final Map<int, Migration> migrations = {
  // 2 adds plugin components ("type": "component"). Nothing to rewrite: the
  // bump only makes older apps refuse these boards instead of failing on an
  // object type they do not know.
  1: (json) => json,
  // 3 adds pictures (type image, bytes kept as assets next to the board) and
  // per-layer name/hidden/locked. All optional, so nothing to rewrite.
  2: (json) => json,
};

class UnsupportedSchemaException extends FormatException {
  const UnsupportedSchemaException(super.message);
}

/// Validates the format marker and runs every migration needed to reach
/// [target]. Refuses files from a newer app instead of silently dropping
/// data it does not understand.
Map<String, Object?> migrateToCurrent(
  Map<String, Object?> json, {
  Map<int, Migration>? steps,
  int target = currentSchemaVersion,
}) {
  final chain = steps ?? migrations;
  if (json['format'] != 'local-board') {
    throw const FormatException('Not a Local Board file');
  }
  final version = json['schemaVersion'];
  if (version is! int || version < 1) {
    throw FormatException('Invalid schemaVersion: $version');
  }
  if (version > target) {
    throw UnsupportedSchemaException(
      'This board was saved by a newer version of Local Board (schema $version). Update the app to open it.',
    );
  }
  var current = Map<String, Object?>.of(json);
  for (var v = version; v < target; v++) {
    final step = chain[v];
    if (step == null) throw StateError('Missing migration from schema $v');
    current = step(current)..['schemaVersion'] = v + 1;
  }
  return current;
}
