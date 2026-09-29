/// Schema version written by this build.
const currentSchemaVersion = 1;

typedef Migration = Map<String, Object?> Function(Map<String, Object?> json);

/// `migrations[n]` upgrades a schema-n document to schema n+1.
/// Add an entry here — never edit an old one — when the format changes (plan §7).
final Map<int, Migration> migrations = {};

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
