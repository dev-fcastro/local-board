import 'dart:math' as math;

import '../geometry.dart';
import '../objects.dart';

/// Visual constants for plugin components, shared by the Flutter renderer and
/// the SVG exporter so a component looks the same in the app and outside it.
abstract final class ComponentStyle {
  static const padding = 12.0;
  static const cardRadius = 10.0;
  static const zoneRadius = 12.0;
  static const borderWidth = 1.5;
  static const cardFill = 0xFFFFFFFF;
  static const labelColor = 0xFF17181A;
  static const labelFontSize = 14.0;
  static const labelLines = 2;
  static const maxIconSize = 44.0;
  static const zoneIconSize = 18.0;
  static const zoneDash = 8.0;
  static const zoneGap = 6.0;

  /// Alpha of the zone's tinted background.
  static const zoneFillAlpha = 0x0F;

  /// Card borders are the component color, softened.
  static int border(int color) => (0x80 << 24) | (color & 0xFFFFFF);

  static int zoneFill(int color) => (zoneFillAlpha << 24) | (color & 0xFFFFFF);

  static double get labelBlock => labelFontSize * 1.3 * labelLines;
}

/// Where the icon and the label of a component go.
final class ComponentLayout {
  const ComponentLayout._(this.icon, this.label);

  /// Square the icon's 24×24 grid is scaled into.
  final Bounds icon;

  /// Box the label is laid out in: centered and up to two lines on a card,
  /// one line after the icon on a zone header.
  final Bounds label;

  factory ComponentLayout.of(ComponentObject c) {
    const pad = ComponentStyle.padding;
    final b = c.bounds;
    if (c.isZone) {
      const s = ComponentStyle.zoneIconSize;
      final top = b.top + (ComponentObject.zoneHeader - s) / 2;
      final icon = Bounds(b.left + pad, top, b.left + pad + s, top + s);
      return ComponentLayout._(
        icon,
        Bounds(icon.right + 8, b.top, math.max(icon.right + 8, b.right - pad), b.top + ComponentObject.zoneHeader),
      );
    }
    final labelTop = math.max(b.top + pad, b.bottom - pad - ComponentStyle.labelBlock);
    final label = Bounds(b.left + pad, labelTop, math.max(b.left + pad, b.right - pad), b.bottom - pad);
    final room = math.min(b.width - pad * 2, labelTop - b.top - pad - 4);
    final s = room.clamp(12.0, ComponentStyle.maxIconSize);
    final cy = (b.top + pad + labelTop) / 2;
    final cx = b.center.x;
    return ComponentLayout._(Bounds(cx - s / 2, cy - s / 2, cx + s / 2, cy + s / 2), label);
  }
}
