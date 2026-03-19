#!/bin/bash
# Install DualSubtitles addon into the Stremio application directory
# This copies the addon files so the shell can auto-launch the addon server

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ADDON_SRC="$PROJECT_DIR/DualSubtitles AddOn"
STREMIO_DIR="${1:-/opt/stremio}"
ADDON_DEST="$STREMIO_DIR/DualSubtitles"

echo "Installing DualSubtitles addon..."
echo "  Source: $ADDON_SRC"
echo "  Destination: $ADDON_DEST"

# Create destination directory
sudo mkdir -p "$ADDON_DEST/src"
sudo mkdir -p "$ADDON_DEST/node_modules"

# Copy addon source files
sudo cp "$ADDON_SRC/index.js" "$ADDON_DEST/"
sudo cp "$ADDON_SRC/package.json" "$ADDON_DEST/"
sudo cp "$ADDON_SRC/src/"*.js "$ADDON_DEST/src/"

# Copy node_modules (required for runtime)
sudo cp -r "$ADDON_SRC/node_modules/"* "$ADDON_DEST/node_modules/"

echo "DualSubtitles addon installed to $ADDON_DEST"
echo ""
echo "The addon will auto-start when Stremio launches."
echo "To activate: Settings → Addons → paste http://127.0.0.1:7000/manifest.json"
