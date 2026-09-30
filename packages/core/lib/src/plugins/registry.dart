import 'network_architecture.dart';
import 'plugin.dart';
import 'software_architecture.dart';

/// Plugins that ship with the app, in the order the library shows them.
const builtInPlugins = <BoardPlugin>[softwareArchitecturePlugin, networkArchitecturePlugin];

BoardPlugin? findPlugin(String id) {
  for (final p in builtInPlugins) {
    if (p.id == id) return p;
  }
  return null;
}

ComponentKind? findComponentKind(String pluginId, String kindId) => findPlugin(pluginId)?.kind(kindId);

/// Drawn for components whose plugin this build does not know (a board
/// made with a newer plugin), so nothing on the board disappears.
const unknownComponentIcon = ComponentIcon([
  IconRect(3, 3, 18, 18, radius: 3),
  IconPath('M9.5 9.5 C9.5 8.1 10.6 7 12 7 C13.4 7 14.5 8.1 14.5 9.5 C14.5 11.5 12 11.5 12 13.5'),
  IconCircle(12, 17, 0.9, filled: true),
]);
