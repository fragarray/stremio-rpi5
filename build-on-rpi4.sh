#!/bin/bash
# =============================================================================
# Stremio — Build on Raspberry Pi 4 (32-bit / armhf)
# =============================================================================
# Scarica il repository e compila il pacchetto .deb direttamente sul device.
#
# Utilizzo:
#   chmod +x build-on-rpi4.sh
#   ./build-on-rpi4.sh
#
# Al termine troverai il file stremio_X.Y.Z_armhf.deb nella cartella corrente.
# Installalo con:
#   sudo apt install ./stremio_X.Y.Z_armhf.deb
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/fragarray/stremio-rpi5.git"
REPO_DIR="stremio-rpi5"

# ---- Colori per output leggibile ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo "=============================================="
echo "  Stremio — build per Raspberry Pi 4 (armhf)"
echo "=============================================="
echo ""

# ---- Verifica architettura ----
ARCH="$(dpkg --print-architecture)"
if [ "${ARCH}" != "armhf" ]; then
    warn "Architettura rilevata: ${ARCH}"
    warn "Questo script è pensato per Raspberry Pi OS 32-bit (armhf)."
    read -r -p "Vuoi continuare comunque? [s/N] " resp
    [[ "${resp,,}" == "s" ]] || exit 1
fi

# ---- Verifica che si stia girando come utente normale (non root) ----
if [ "$(id -u)" -eq 0 ]; then
    error "Non eseguire questo script come root. Usa un utente normale; sudo verrà chiesto dove necessario."
fi

# ---- Step 1: Dipendenze di build ----
info "[1/5] Installazione dipendenze di build..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    pkgconf \
    git \
    wget \
    librsvg2-bin \
    libssl-dev \
    libmpv-dev \
    qtbase5-dev \
    qtdeclarative5-dev \
    qtwebengine5-dev \
    libqt5webchannel5-dev \
    libqt5dbus5 \
    libqt5opengl5-dev \
    qml-module-qtwebchannel \
    qml-module-qtwebengine \
    qml-module-qt-labs-platform \
    qml-module-qtquick-dialogs \
    qml-module-qtquick-controls \
    qml-module-qt-labs-settings \
    qml-module-qt-labs-folderlistmodel \
    nodejs \
    npm

# ---- Step 2: Clone del repository ----
info "[2/5] Download del repository..."
if [ -d "${REPO_DIR}" ]; then
    warn "La cartella '${REPO_DIR}' esiste già."
    read -r -p "Aggiornare con git pull? [S/n] " resp
    if [[ "${resp,,}" != "n" ]]; then
        cd "${REPO_DIR}"
        git pull
        git submodule update --init --recursive
        cd ..
    fi
else
    git clone --recurse-submodules "${REPO_URL}" "${REPO_DIR}"
fi

cd "${REPO_DIR}"

# ---- Fallback submoduli (nel caso cloni parziali) ----
if [ ! -f deps/singleapplication/CMakeLists.txt ]; then
    warn "Submodulo SingleApplication mancante, clono manualmente..."
    rm -rf deps/singleapplication
    git clone https://github.com/itay-grudev/SingleApplication deps/singleapplication
fi
if [ ! -f deps/libmpv/include/mpv/client.h ]; then
    warn "Submodulo libmpv mancante, clono manualmente..."
    rm -rf deps/libmpv
    git clone https://github.com/Ivshti/libmpv deps/libmpv
fi

# ---- Step 3: Dipendenze addon ----
info "[3/5] Installazione dipendenze addon DualSubtitles..."
cd "DualSubtitles AddOn"
npm install --production
cd ..

# ---- Step 4: Build .deb ----
info "[4/5] Compilazione e packaging (ci vorrà un po'—armhf è lento)..."
chmod +x scripts/build-deb.sh scripts/stremio-launcher.sh

# Forza armhf indipendentemente dall'output di dpkg (sicurezza in caso di ambienti ibridi)
ARCH=armhf bash scripts/build-deb.sh --compile

# ---- Step 5: Copia il .deb nella cartella originale ----
info "[5/5] Copia del pacchetto nella cartella di partenza..."
DEB_FILE="$(ls stremio_*_armhf.deb 2>/dev/null | head -n1)"
if [ -z "${DEB_FILE}" ]; then
    error "Nessun file .deb trovato dopo il build. Controlla l'output sopra."
fi

DEST_DIR="$(cd .. && pwd)"
cp "${DEB_FILE}" "${DEST_DIR}/"

echo ""
echo "=============================================="
echo "  Build completato con successo!"
echo ""
echo "  Pacchetto: ${DEST_DIR}/${DEB_FILE}"
echo ""
echo "  Installa con:"
echo "    sudo apt install ${DEST_DIR}/${DEB_FILE}"
echo "=============================================="
