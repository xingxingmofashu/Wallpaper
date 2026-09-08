#!/bin/bash
# One-click install/uninstall for the vw CLI.
#
# Usage:
#   scripts/install.sh             Build (Release) and install vw
#   scripts/install.sh --uninstall Stop the instance and remove installed files
#   VW_PREFIX=/some/dir scripts/install.sh   Install to a custom prefix
#
# Install location (first match wins):
#   1. $VW_PREFIX          if set
#   2. /usr/local/bin      if writable
#   3. /opt/homebrew/bin   if writable (no sudo needed)
#   4. /usr/local/bin      via sudo (will prompt for password)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Wallpaper.xcodeproj"
BUILT="$ROOT/build/Build/Products/Release/Wallpaper"
APP_DIR="$HOME/.vw"

resolve_dest() {
    if [ -n "${VW_PREFIX:-}" ]; then
        echo "$VW_PREFIX"
    elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        echo "/usr/local/bin"
    elif [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
        echo "/opt/homebrew/bin"
    else
        echo "/usr/local/bin"
    fi
}

DEST_DIR="$(resolve_dest)"
DEST="$DEST_DIR/vw"

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
    echo "Uninstalled from $DEST."
}

[ "${1:-}" = "--uninstall" ] && uninstall && exit 0

command -v xcodebuild >/dev/null 2>&1 \
    || { echo "error: xcodebuild not found, please install Xcode first" >&2; exit 1; }
[ -d "$PROJECT" ] || { echo "error: project not found at $PROJECT" >&2; exit 1; }

echo "Building (Release)..."
xcodebuild -project "$PROJECT" -scheme Wallpaper -configuration Release \
    build -derivedDataPath "$ROOT/build" -quiet
[ -f "$BUILT" ] || { echo "error: build product not found at $BUILT" >&2; exit 1; }

echo "Installing to $DEST..."
$SUDO mkdir -p "$DEST_DIR"
$SUDO rm -f "$DEST"
$SUDO cp -f "$BUILT" "$DEST"

echo "Installed: $("$DEST" version)"

case ":$PATH:" in
    *":$DEST_DIR:"*) ;;
    *) echo "note: add $DEST_DIR to your PATH to use vw from anywhere" ;;
esac

echo
echo "Usage:"
echo "  vw run ~/Videos/wallpaper.mov   Play a video wallpaper"
echo "  vw stop                         Stop the running instance"
echo "  vw help                         Show full help"
