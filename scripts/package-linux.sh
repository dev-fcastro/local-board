#!/usr/bin/env bash
# Builds the Linux release and packages it into dist/:
#   LocalBoard-<version>-x86_64.AppImage   (+ LocalBoard-x86_64.AppImage alias)
#   LocalBoard-<version>-linux-x86_64.tar.gz (+ LocalBoard-linux-x86_64.tar.gz alias)
#   SHA256SUMS
# The un-versioned aliases are what the website's "latest" download links use.
#
# Usage: scripts/package-linux.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

VERSION=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' apps/desktop/pubspec.yaml)
ID=dev.fcastro.LocalBoard
PKG=apps/desktop/linux/packaging
BUNDLE=apps/desktop/build/linux/x64/release/bundle
DIST=$ROOT/dist
WORK=$ROOT/build/package
TOOLS=$ROOT/build/tools

echo "==> Local Board $VERSION"

if [[ "${1:-}" != "--skip-build" ]]; then
  (cd apps/desktop && flutter build linux --release --build-name="$VERSION")
fi
[[ -x "$BUNDLE/local-board" ]] || { echo "missing $BUNDLE/local-board"; exit 1; }

rm -rf "$WORK" && mkdir -p "$WORK" "$DIST" "$TOOLS"

# ---------- tar.gz: bundle + desktop integration files + installer ----------
TARDIR=$WORK/local-board
cp -r "$BUNDLE" "$TARDIR"
mkdir -p "$TARDIR/share"
cp -r "$PKG/icons" "$TARDIR/share/icons"
cp "$PKG/$ID.desktop" "$PKG/local-board-mime.xml" "$TARDIR/share/"
cp LICENSE "$TARDIR/" 2>/dev/null || true
echo "$VERSION" > "$TARDIR/VERSION"
TAR=LocalBoard-$VERSION-linux-x86_64.tar.gz
tar -C "$WORK" -czf "$DIST/$TAR" local-board
cp "$DIST/$TAR" "$DIST/LocalBoard-linux-x86_64.tar.gz"
echo "==> $TAR"

# ---------- AppImage ----------
APPDIR=$WORK/LocalBoard.AppDir
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/metainfo"
cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"
for s in 16 24 32 48 64 128 256 512; do
  install -Dm644 "$PKG/icons/$s.png" "$APPDIR/usr/share/icons/hicolor/${s}x${s}/apps/$ID.png"
done
install -Dm644 "$PKG/icons/scalable.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/$ID.svg"
install -Dm644 "$PKG/local-board-mime.xml" "$APPDIR/usr/share/mime/packages/$ID.xml"
cp "$PKG/$ID.desktop" "$APPDIR/usr/share/applications/"
cp "$PKG/$ID.desktop" "$APPDIR/$ID.desktop"
cp "$PKG/icons/256.png" "$APPDIR/$ID.png"
cp "$PKG/icons/256.png" "$APPDIR/.DirIcon"
cp "$PKG/$ID.metainfo.xml" "$APPDIR/usr/share/metainfo/"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/local-board" "$@"
EOF
chmod +x "$APPDIR/AppRun"

APPIMAGETOOL=$TOOLS/appimagetool-x86_64.AppImage
if [[ ! -x "$APPIMAGETOOL" ]]; then
  curl -fsSL -o "$APPIMAGETOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$APPIMAGETOOL"
fi
APPIMAGE=LocalBoard-$VERSION-x86_64.AppImage
# --appimage-extract-and-run: works without FUSE (CI containers).
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$DIST/$APPIMAGE" >/dev/null
cp "$DIST/$APPIMAGE" "$DIST/LocalBoard-x86_64.AppImage"
echo "==> $APPIMAGE"

(cd "$DIST" && sha256sum LocalBoard-* > SHA256SUMS)
ls -lh "$DIST"
