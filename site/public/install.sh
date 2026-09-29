#!/bin/sh
# Local Board installer for Linux (x86_64). No root needed.
#
#   curl -fsSL https://localboard-one.vercel.app/install.sh | sh
#
# Installs the latest release into ~/.local, adds it to your app launcher with
# its icon, and registers .whiteboard files. Re-run to update.
# Uninstall:  curl -fsSL https://localboard-one.vercel.app/install.sh | sh -s -- --uninstall
# Your boards (~/.local/share/local-board) are never touched.
set -eu

REPO="dev-fcastro/local-board"
ID="dev.fcastro.LocalBoard"
VERSION="${LOCAL_BOARD_VERSION:-latest}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
OPT="$HOME/.local/opt/local-board"
BIN="$HOME/.local/bin"

say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

refresh() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA/applications" 2>/dev/null || true
  command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$DATA/mime" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$DATA/icons/hicolor" 2>/dev/null || true
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$OPT"
  rm -f "$BIN/local-board" "$DATA/applications/$ID.desktop" "$DATA/mime/packages/$ID.xml"
  for d in "$DATA"/icons/hicolor/*/apps; do rm -f "$d/$ID.png" "$d/$ID.svg"; done
  refresh
  say "Local Board removed. Your boards in $DATA/local-board were kept."
  exit 0
fi

[ "$(uname -s)" = "Linux" ] || die "This installer is for Linux. Windows and macOS versions are not available yet."
case "$(uname -m)" in x86_64|amd64) ;; *) die "Only x86_64 is supported for now (found $(uname -m))." ;; esac
command -v tar >/dev/null 2>&1 || die "tar is required."

if command -v curl >/dev/null 2>&1; then fetch() { curl -fL --progress-bar -o "$1" "$2"; }
elif command -v wget >/dev/null 2>&1; then fetch() { wget -q --show-progress -O "$1" "$2"; }
else die "curl or wget is required."; fi

if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/$REPO/releases/latest/download/LocalBoard-linux-x86_64.tar.gz"
else
  URL="https://github.com/$REPO/releases/download/v$VERSION/LocalBoard-$VERSION-linux-x86_64.tar.gz"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Downloading Local Board ($VERSION)…"
fetch "$TMP/lb.tar.gz" "$URL" || die "Download failed: $URL"
tar -xzf "$TMP/lb.tar.gz" -C "$TMP"
[ -x "$TMP/local-board/local-board" ] || die "Unexpected archive layout."

say "Installing to $OPT"
rm -rf "$OPT"
mkdir -p "$(dirname "$OPT")" "$BIN" "$DATA/applications" "$DATA/mime/packages"
mv "$TMP/local-board" "$OPT"
ln -sf "$OPT/local-board" "$BIN/local-board"

for s in 16 24 32 48 64 128 256 512; do
  mkdir -p "$DATA/icons/hicolor/${s}x${s}/apps"
  cp "$OPT/share/icons/$s.png" "$DATA/icons/hicolor/${s}x${s}/apps/$ID.png"
done
mkdir -p "$DATA/icons/hicolor/scalable/apps"
cp "$OPT/share/icons/scalable.svg" "$DATA/icons/hicolor/scalable/apps/$ID.svg"
sed "s|^Exec=.*|Exec=$OPT/local-board %f|" "$OPT/share/$ID.desktop" > "$DATA/applications/$ID.desktop"
cp "$OPT/share/local-board-mime.xml" "$DATA/mime/packages/$ID.xml"
refresh

say "Local Board $(cat "$OPT/VERSION" 2>/dev/null || echo "") installed."
echo "    Open it from your app launcher, or run: local-board"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "    (Add $BIN to your PATH to use the 'local-board' command.)" ;; esac
