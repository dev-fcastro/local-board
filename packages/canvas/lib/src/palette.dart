/// Colors derived from the Local Board site tokens (tokens.css).
abstract final class Palette {
  static const canvas = 0xFFFAF9F9;
  static const ink = 0xFF17181A;
  static const inkSecondary = 0xFF55585E;
  static const inkTertiary = 0xFF8A8D93;
  static const accent = 0xFF4F46E5;
  static const gridDot = 0x3317181A;

  /// Pen / shape / text colors.
  static const inks = <int>[
    ink,
    accent,
    0xFFDC2626, // red
    0xFFEA580C, // orange
    0xFF16A34A, // green
    0xFF0891B2, // teal
    inkTertiary,
  ];

  static const stickies = <int>[
    0xFFFFE08A, // amber
    0xFFFFC2D1, // pink
    0xFFB9F0C9, // mint
    0xFFBFD7FF, // sky
    0xFFE3D5FF, // lilac
  ];

  static const strokeWidths = <double>[2, 4, 8];
  static const textSizes = <double>[16, 24, 40];
}
