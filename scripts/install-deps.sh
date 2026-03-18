#!/bin/bash
# =============================================================================
# Stremio Dependency Installer for Raspberry Pi 5 (arm64)
# Ubuntu 24.04+ / Debian Bookworm+
# =============================================================================
# Run this BEFORE building Stremio from source.
# It installs both build-time and runtime dependencies.
# =============================================================================

set -euo pipefail

echo "============================================"
echo " Stremio Dependencies Installer (arm64)"
echo "============================================"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (sudo)."
    exit 1
fi

echo "[1/3] Updating package lists..."
apt-get update

echo ""
echo "[2/3] Installing BUILD dependencies..."
apt-get install -y \
    build-essential \
    cmake \
    g++ \
    pkg-config \
    git \
    wget \
    librsvg2-bin \
    libssl-dev \
    libmpv-dev \
    qtbase5-dev \
    qtdeclarative5-dev \
    qtwebengine5-dev \
    libqt5opengl5-dev \
    libqt5webchannel5-dev

echo ""
echo "[3/3] Installing RUNTIME dependencies..."
apt-get install -y \
    nodejs \
    libmpv2 \
    libqt5webengine5 \
    libqt5webenginecore5 \
    libqt5webchannel5 \
    libqt5qml5 \
    libqt5quick5 \
    libqt5webengine-data \
    qml-module-qtwebengine \
    qml-module-qtwebchannel \
    qml-module-qtquick-controls \
    qml-module-qtquick-dialogs \
    qml-module-qt-labs-platform \
    qml-module-qt-labs-settings \
    qml-module-qt-labs-folderlistmodel \
    librubberband2 \
    libuchardet0 \
    xdg-utils

# Optional but recommended
apt-get install -y libfdk-aac2 2>/dev/null || \
    echo "Note: libfdk-aac2 not available, skipping (non-critical)"

echo ""
echo "============================================"
echo " All dependencies installed successfully!"
echo ""
echo " To build Stremio:"
echo "   cd stremio-shell-master"
echo "   ./scripts/build-deb.sh --compile"
echo ""
echo " Or to build manually:"
echo "   mkdir -p build && cd build"
echo "   cmake -DCMAKE_BUILD_TYPE=Release .."
echo "   make -j\$(nproc)"
echo "============================================"
