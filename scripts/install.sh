#!/bin/bash
# Install the vw CLI built from this repository.
#
# Usage:
#   scripts/install.sh             Build (Release) and install to /usr/local/bin/vw
#   scripts/install.sh --uninstall Stop the instance and remove installed files
set -euo pipefail

DEST_DIR="/usr/local/bin"
DEST="$DEST_DIR/vw"
APP_DIR="$HOME/.vw"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Wallpaper.xcodeproj"
BUILT="$ROOT/build/Build/Products/Release/Wallpaper"

SUDO=""
if [ ! -d "$DEST_DIR" ] || [ ! -w "$DEST_DIR" ]; then
    SUDO="sudo"
fi

uninstall() {
    if [ -x "$DEST" ]; then
        "$DEST" stop || true
    fi
    $SUDO rm -f "$DEST"
    rm -rf "$APP_DIR"
    echo "Uninstalled."
}

[ "${1:-}" = "--uninstall" ] && uninstall && exit 0

[ -d "$PROJECT" ] || { echo "error: project not found at $PROJECT" >&2; exit 1; }

echo "Building (Release)..."
xcodebuild -project "$PROJECT" -scheme Wallpaper -configuration Release \
    build -derivedDataPath "$ROOT/build" -quiet
[ -f "$BUILT" ] || { echo "error: build product not found at $BUILT" >&2; exit 1; }

echo "Installing to $DEST..."
$SUDO mkdir -p "$DEST_DIR"
$SUDO cp -f "$BUILT" "$DEST"

echo "Installed: $("$DEST" version)"
echo
echo "Usage:"
echo "  vw run ~/Videos/wallpaper.mov   Play a video wallpaper"
echo "  vw stop                         Stop the running instance"
echo "  vw help                         Show full help"
