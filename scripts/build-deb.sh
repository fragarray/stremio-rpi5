#!/bin/bash
# =============================================================================
# Stremio Debian Package Builder for Raspberry Pi 5 (arm64)
# =============================================================================
# This script builds a .deb package for Stremio on ARM64/aarch64 systems.
#
# Usage:
#   ./build-deb.sh                  # Build using pre-compiled binary
#   ./build-deb.sh --compile        # Compile from source first, then package
#
# Requirements (for compilation):
#   Build deps: cmake, g++, pkg-config, libssl-dev, libmpv-dev,
#               qtbase5-dev, qtdeclarative5-dev, qtwebengine5-dev,
#               libqt5opengl5-dev, librsvg2-bin
#
# The resulting .deb will be placed in the current directory.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${SOURCE_DIR}/build"

# Extract version from CMakeLists.txt
VERSION=$(sed -E '/^project\(/!d;s/^.*VERSION "([^"]+)".*$/\1/g' "${SOURCE_DIR}/CMakeLists.txt")
ARCH="arm64"
PKG_NAME="stremio"
PKG_DIR="${SOURCE_DIR}/deb-build/${PKG_NAME}_${VERSION}_${ARCH}"

SERVER_URL=$(cat "${SOURCE_DIR}/server-url.txt" | tr -d '[:space:]')

COMPILE=false
if [ "${1:-}" = "--compile" ]; then
    COMPILE=true
fi

echo "======================================"
echo "Stremio .deb builder"
echo "Version: ${VERSION}"
echo "Arch:    ${ARCH}"
echo "======================================"

# ---- Step 1: Compile if requested ----
if [ "${COMPILE}" = true ]; then
    echo ""
    echo "[1/5] Compiling Stremio from source..."
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    cmake -G"Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="" \
        "${SOURCE_DIR}"
    make -j"$(nproc)"
    cd "${SOURCE_DIR}"
else
    echo ""
    echo "[1/5] Skipping compilation (use --compile to build from source)"
    if [ ! -f "${BUILD_DIR}/stremio" ]; then
        echo "Error: ${BUILD_DIR}/stremio not found. Run with --compile or build first." >&2
        exit 1
    fi
fi

# ---- Step 2: Download server.js if not present ----
echo ""
echo "[2/5] Checking server.js..."
if [ ! -f "${SOURCE_DIR}/server.js" ]; then
    echo "Downloading server.js from ${SERVER_URL}..."
    wget "${SERVER_URL}" -qO "${SOURCE_DIR}/server.js" || {
        echo "Error: Failed to download server.js" >&2
        exit 1
    }
fi

# ---- Step 3: Generate icons ----
echo ""
echo "[3/5] Generating icons..."
ICONS_DIR="${SOURCE_DIR}/icons"
mkdir -p "${ICONS_DIR}"
cd "${ICONS_DIR}"
for size in 16 22 24 32 48 64 128 256; do
    rsvg-convert "${SOURCE_DIR}/images/stremio.svg" -w ${size} -o "smartcode-stremio_${size}.png" 2>/dev/null || true
    rsvg-convert "${SOURCE_DIR}/images/stremio_tray_white.svg" -w ${size} -o "smartcode-stremio-tray_${size}.png" 2>/dev/null || true
done
cd "${SOURCE_DIR}"

# ---- Step 4: Build package directory structure ----
echo ""
echo "[4/5] Building package structure..."

# Clean previous build
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}"

# /opt/stremio - main application directory
INSTALL_DIR="${PKG_DIR}/opt/stremio"
mkdir -p "${INSTALL_DIR}"

# Install binary
install -Dm 755 "${BUILD_DIR}/stremio" "${INSTALL_DIR}/stremio"

# Install server.js
install -Dm 644 "${SOURCE_DIR}/server.js" "${INSTALL_DIR}/server.js"

# Install launcher script
install -Dm 755 "${SOURCE_DIR}/scripts/stremio-launcher.sh" "${INSTALL_DIR}/stremio-launcher"

# Install desktop file
install -Dm 644 "${SOURCE_DIR}/smartcode-stremio.desktop" "${INSTALL_DIR}/smartcode-stremio.desktop"

# Install icons
cp -r "${ICONS_DIR}" "${INSTALL_DIR}/"

# Install SVG icon for hi-res
install -Dm 644 "${SOURCE_DIR}/images/stremio.svg" "${INSTALL_DIR}/stremio.svg"

# Install DualSubtitles addon
ADDON_SRC="${SOURCE_DIR}/DualSubtitles AddOn"
ADDON_DEST="${INSTALL_DIR}/DualSubtitles"
if [ -d "${ADDON_SRC}" ]; then
    echo "  Including DualSubtitles addon..."
    mkdir -p "${ADDON_DEST}/src"
    install -Dm 644 "${ADDON_SRC}/index.js" "${ADDON_DEST}/index.js"
    install -Dm 644 "${ADDON_SRC}/package.json" "${ADDON_DEST}/package.json"
    install -Dm 644 "${ADDON_SRC}/package-lock.json" "${ADDON_DEST}/package-lock.json" 2>/dev/null || true
    for f in "${ADDON_SRC}/src/"*.js; do
        [ -f "$f" ] && install -Dm 644 "$f" "${ADDON_DEST}/src/$(basename "$f")"
    done
    # Bundle node_modules for offline install
    if [ -d "${ADDON_SRC}/node_modules" ]; then
        cp -a "${ADDON_SRC}/node_modules" "${ADDON_DEST}/"
    fi
else
    echo "  Warning: DualSubtitles addon source not found, skipping."
fi

# Create node symlink (will be resolved at postinst if needed)
# We don't bundle node - we depend on the nodejs package

# /usr/bin/stremio - launcher symlink handled by postinst
mkdir -p "${PKG_DIR}/usr/bin"

# /usr/share/applications - desktop entry
mkdir -p "${PKG_DIR}/usr/share/applications"
cat > "${PKG_DIR}/usr/share/applications/stremio.desktop" << 'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Stremio
Comment=Video organizer for your Movies, TV Shows and TV Channels
Exec=stremio %U
Icon=smartcode-stremio
Terminal=false
Type=Application
Categories=AudioVideo;Video;Player;TV;
MimeType=application/x-bittorrent;x-scheme-handler/magnet;x-scheme-handler/stremio;video/avi;video/msvideo;video/x-msvideo;video/mp4;video/x-matroska;
StartupWMClass=stremio
DESKTOP

# /usr/share/icons - scalable SVG icon
mkdir -p "${PKG_DIR}/usr/share/icons/hicolor/scalable/apps"
install -Dm 644 "${SOURCE_DIR}/images/stremio.svg" \
    "${PKG_DIR}/usr/share/icons/hicolor/scalable/apps/smartcode-stremio.svg"

# PNG icons at standard sizes
for size in 16 22 24 32 48 64 128 256; do
    icon_file="${ICONS_DIR}/smartcode-stremio_${size}.png"
    if [ -f "${icon_file}" ]; then
        icon_dir="${PKG_DIR}/usr/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "${icon_dir}"
        install -Dm 644 "${icon_file}" "${icon_dir}/smartcode-stremio.png"
    fi
done

# ---- DEBIAN control files ----
DEBIAN_DIR="${PKG_DIR}/DEBIAN"
mkdir -p "${DEBIAN_DIR}"

# Compute installed size in KB
INSTALLED_SIZE=$(du -sk "${PKG_DIR}" | cut -f1)

cat > "${DEBIAN_DIR}/control" << CONTROL
Package: ${PKG_NAME}
Version: ${VERSION}
Section: video
Priority: optional
Architecture: ${ARCH}
Depends: nodejs (>= 12.0.0), libmpv2 (>= 0.30.0), libqt5webengine5 (>= 5.15.0), libqt5webenginecore5 (>= 5.15.0), libqt5webchannel5 (>= 5.15.0), libqt5widgets5t64 (>= 5.15.0) | libqt5widgets5 (>= 5.15.0), libqt5gui5t64 (>= 5.15.0) | libqt5gui5 (>= 5.15.0), libqt5qml5 (>= 5.15.0), libqt5quick5 (>= 5.15.0), libqt5network5t64 (>= 5.15.0) | libqt5network5 (>= 5.15.0), libqt5dbus5t64 (>= 5.15.0) | libqt5dbus5 (>= 5.15.0), libqt5opengl5t64 (>= 5.15.0) | libqt5opengl5 (>= 5.15.0), libqt5core5t64 (>= 5.15.0) | libqt5core5a (>= 5.15.0), qml-module-qtwebengine (>= 5.15.0), qml-module-qtwebchannel (>= 5.15.0), qml-module-qtquick-controls (>= 5.15.0), qml-module-qtquick-dialogs (>= 5.15.0), qml-module-qt-labs-platform (>= 5.15.0), qml-module-qt-labs-settings (>= 5.15.0), qml-module-qt-labs-folderlistmodel (>= 5.15.0), libssl3t64 (>= 3.0.0) | libssl3 (>= 3.0.0) | libssl1.1 (>= 1.1.0), librubberband2 (>= 1.8.0), libuchardet0 (>= 0.0.6), libqt5webengine-data
Recommends: libfdk-aac2, xdg-utils
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Stremio Community <stremio@community.arm64>
Homepage: https://www.stremio.com
Description: Stremio - Freedom to Stream
 Stremio is a modern media center that gives you the freedom to stream your
 favorite content. It aggregates video content from multiple sources including
 movies, TV shows, series, and live TV channels.
 .
 This package is built for Raspberry Pi 5 (arm64/aarch64) running Ubuntu.
 It includes the Stremio shell (Qt5/WebEngine UI), the Node.js streaming
 server backend, and the DualSubtitles addon for dual subtitle display.
 .
 The DualSubtitles addon starts automatically with Stremio. To activate it,
 go to Settings → Addons and install http://127.0.0.1:7000/manifest.json
CONTROL

# postinst script
cat > "${DEBIAN_DIR}/postinst" << 'POSTINST'
#!/bin/bash
set -e

# Create node symlink in /opt/stremio if not present
if [ ! -e /opt/stremio/node ]; then
    NODE_PATH=$(command -v node 2>/dev/null || command -v nodejs 2>/dev/null || true)
    if [ -n "${NODE_PATH}" ]; then
        ln -sf "${NODE_PATH}" /opt/stremio/node
    fi
fi

# Create launcher symlink
ln -sf /opt/stremio/stremio-launcher /usr/bin/stremio

# Update desktop database
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi

# Update icon cache
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi

# Update MIME database
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime 2>/dev/null || true
fi

# Install DualSubtitles addon dependencies if node_modules not bundled
if [ -d /opt/stremio/DualSubtitles ] && [ -f /opt/stremio/DualSubtitles/package.json ]; then
    if [ ! -d /opt/stremio/DualSubtitles/node_modules ]; then
        echo "Installing DualSubtitles addon dependencies..."
        NODE_BIN=$(command -v node 2>/dev/null || command -v nodejs 2>/dev/null || true)
        NPM_BIN=$(command -v npm 2>/dev/null || true)
        if [ -n "${NPM_BIN}" ]; then
            cd /opt/stremio/DualSubtitles && "${NPM_BIN}" install --production 2>/dev/null || true
            cd /
        fi
    fi
fi

echo ""
echo "============================================"
echo "  Stremio installed successfully!"
echo "  Run 'stremio' or launch from the menu."
echo ""
echo "  DualSubtitles addon included."
echo "  Activate in Stremio: Settings → Addons →"
echo "  http://127.0.0.1:7000/manifest.json"
echo "============================================"
echo ""
POSTINST
chmod 755 "${DEBIAN_DIR}/postinst"

# prerm script
cat > "${DEBIAN_DIR}/prerm" << 'PRERM'
#!/bin/bash
set -e

# Remove symlinks
rm -f /usr/bin/stremio
rm -f /opt/stremio/node

# Update desktop database
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi

# Update icon cache
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
PRERM
chmod 755 "${DEBIAN_DIR}/prerm"

# postrm script
cat > "${DEBIAN_DIR}/postrm" << 'POSTRM'
#!/bin/bash
set -e

if [ "$1" = "purge" ]; then
    rm -rf /opt/stremio
fi
POSTRM
chmod 755 "${DEBIAN_DIR}/postrm"

# conffiles (none, but create empty for good practice)
touch "${DEBIAN_DIR}/conffiles"

# ---- Step 5: Build the .deb ----
echo ""
echo "[5/5] Building .deb package..."

DEB_FILE="${SOURCE_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "${PKG_DIR}" "${DEB_FILE}"

echo ""
echo "======================================"
echo "Package built successfully!"
echo "  ${DEB_FILE}"
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${DEB_FILE}"
echo "  sudo apt-get install -f   # fix any missing dependencies"
echo ""
echo "Or install with automatic dependency resolution:"
echo "  sudo apt install ./${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "======================================"

# Show package info
echo ""
echo "Package details:"
dpkg-deb --info "${DEB_FILE}"
echo ""
echo "Package contents:"
dpkg-deb --contents "${DEB_FILE}" | head -30 || true
