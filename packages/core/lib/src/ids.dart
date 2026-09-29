import 'dart:math';

final Random _random = Random.secure();

/// A 128-bit random identifier as 32 hex chars. Stable across saves and
/// devices; never derived from array position (see plan §6).
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 4; i++) {
    b.write(_random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'));
  }
  return b.toString();
}
