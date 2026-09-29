#!/usr/bin/env bash
# Installs the release build for the current user (no root):
#   ~/.local/opt/local-board/        app bundle
#   ~/.local/bin/local-board         launcher symlink
#   ~/.local/share/applications/     .desktop entry (app launcher)
#   ~/.local/share/icons/hicolor/    app icon at every size
#   ~/.local/share/mime/             .whiteboard file type
# Uninstall: scripts/install-local.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")/.."

ID=dev.fcastro.LocalBoard
PKG=apps/desktop/linux/packaging
BUNDLE=apps/desktop/build/linux/x64/release/bundle
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
OPT=$HOME/.local/opt/local-board
BIN=$HOME/.local/bin

refresh() {
  update-desktop-database "$DATA/applications" 2>/dev/null || true
  update-mime-database "$DATA/mime" 2>/dev/null || true
  gtk-update-icon-cache -f -t "$DATA/icons/hicolor" 2>/dev/null || true
}

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$OPT"
  rm -f "$BIN/local-board" "$DATA/applications/$ID.desktop" "$DATA/mime/packages/$ID.xml"
  for d in "$DATA"/icons/hicolor/*/apps; do rm -f "$d/$ID.png" "$d/$ID.svg"; done
  refresh
  echo "Local Board uninstalled (your boards in $DATA/local-board were kept)."
  exit 0
fi

[[ -x "$BUNDLE/local-board" ]] || { echo "Build first: (cd apps/desktop && flutter build linux --release)"; exit 1; }

mkdir -p "$OPT" "$BIN" "$DATA/applications" "$DATA/mime/packages"
rm -rf "$OPT" && cp -r "$BUNDLE" "$OPT"
ln -sf "$OPT/local-board" "$BIN/local-board"

for s in 16 24 32 48 64 128 256 512; do
  install -Dm644 "$PKG/icons/$s.png" "$DATA/icons/hicolor/${s}x${s}/apps/$ID.png"
done
install -Dm644 "$PKG/icons/scalable.svg" "$DATA/icons/hicolor/scalable/apps/$ID.svg"

sed "s|^Exec=.*|Exec=$OPT/local-board %f|" "$PKG/$ID.desktop" > "$DATA/applications/$ID.desktop"
install -Dm644 "$PKG/local-board-mime.xml" "$DATA/mime/packages/$ID.xml"
refresh
echo "Installed. Open 'Local Board' from your app launcher, or run: local-board"
