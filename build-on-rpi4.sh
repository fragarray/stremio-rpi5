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

# ---- Rileva versione Debian/Raspbian ----
DISTRO_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")"
info "Distribuzione rilevata: ${DISTRO_CODENAME}"

# ---- Blocco su Trixie (Debian 13): Qt WebEngine non disponibile per armhf ----
#
# Debian Trixie (13) ha rimosso Qt5 WebEngine dai repository perché conteneva
# una versione vecchia di Chromium. Qt6 WebEngine non è pacchettizzato per
# armhf (32-bit) perché la compilazione di Chromium richiede un toolchain
# a 64-bit per generare gli snapshot V8.
#
# In pratica: su armhf + Trixie NON esiste alcun Qt WebEngine installabile
# tramite apt, e Stremio non può essere compilato senza di esso.
#
if [ "${DISTRO_CODENAME}" = "trixie" ] || [ "${DISTRO_CODENAME}" = "forky" ]; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ERRORE: distribuzione non compatibile con il build 32-bit  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Stai usando Raspberry Pi OS basato su Debian ${DISTRO_CODENAME} (13).${NC}"
    echo ""
    echo "Il problema: Stremio usa Qt WebEngine (un browser Chromium integrato)"
    echo "che NON è disponibile come pacchetto per armhf (32-bit) su Trixie:"
    echo ""
    echo "  • Qt5 WebEngine  → rimosso da Debian 13 (Chromium obsoleto)"
    echo "  • Qt6 WebEngine  → non pacchettizzato per armhf (richiede 64-bit build tools)"
    echo ""
    echo -e "${GREEN}Soluzioni:${NC}"
    echo ""
    echo "  1. [RACCOMANDATA] Usa Raspberry Pi OS BOOKWORM 32-bit (Debian 12):"
    echo "     https://www.raspberrypi.com/software/operating-systems/"
    echo "     → Seleziona 'Raspberry Pi OS (Legacy, 32-bit)' — basato su Bookworm"
    echo "     → Qt5 WebEngine è disponibile e funzionante"
    echo ""
    echo "  2. Usa Raspberry Pi OS a 64-bit (Bookworm o Trixie):"
    echo "     → Supportato nativamente da questo progetto (RPi5 build)"
    echo "     → Qt WebEngine è disponibile per arm64"
    echo ""
    exit 1
fi

# ---- Step 1: Dipendenze di build ----
info "[1/5] Installazione dipendenze di build..."

# Rimuovi eventuale sorgente Debian rimasta da un run precedente fallito,
# così il primo apt-get update parte sempre da uno stato pulito.
sudo rm -f /etc/apt/sources.list.d/debian-bookworm-qtwebengine.list
sudo rm -f /etc/apt/keyrings/debian-archive-keyring.gpg

sudo apt-get update

# Su Bookworm il pacchetto si chiama libqt5dbus5; su distro future potrebbe
# cambiare nome (t64 transition). Proviamo prima il nome canonico, poi il t64.
QT_DBUS_PKG="libqt5dbus5"
if ! apt-cache show "${QT_DBUS_PKG}" >/dev/null 2>&1; then
    QT_DBUS_PKG="libqt5dbus5t64"
    warn "libqt5dbus5 non trovato, uso ${QT_DBUS_PKG}"
fi

# ---- Raspbian non include Qt WebEngine: aggiungi Debian Bookworm come sorgente ----
#
# Raspbian (il fork armhf della Raspberry Pi Foundation) non compila Qt WebEngine
# nei propri repository, nemmeno su Bookworm. Il pacchetto esiste però nel repo
# Debian Bookworm ufficiale, che è ABI-compatibile con Raspbian.
# Aggiungiamo quel repo con priorità bassa (100) e alziamo la priorità solo per
# i pacchetti Qt WebEngine, evitando di sovrascrivere il resto del sistema.
#
if ! apt-cache show qtwebengine5-dev >/dev/null 2>&1; then
    warn "qtwebengine5-dev non trovato in Raspbian. Raspbian non include Qt WebEngine."
    warn "Aggiungo il repository Debian Bookworm ufficiale (solo per i pacchetti mancanti)..."

    # Chiave GPG di Debian — su Raspbian il pacchetto debian-archive-keyring
    # non esiste, scarichiamo le chiavi direttamente dal keyserver Ubuntu.
    info "Scarico le chiavi GPG di Debian..."
    rm -f /tmp/debian-keys.gpg
    for KEY in 6ED0E7B82643E131 78DBA3BC47EF2265 F8D2585B8783D481; do
        wget -qO- "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${KEY}" \
            | gpg --dearmor >> /tmp/debian-keys.gpg \
            || error "Impossibile scaricare la chiave GPG ${KEY}. Controlla la connessione."
    done
    sudo install -m 0644 /tmp/debian-keys.gpg \
        /etc/apt/keyrings/debian-archive-keyring.gpg
    rm -f /tmp/debian-keys.gpg

    # Repository Debian Bookworm
    echo "deb [signed-by=/etc/apt/keyrings/debian-archive-keyring.gpg] \
http://deb.debian.org/debian bookworm main" \
        | sudo tee /etc/apt/sources.list.d/debian-bookworm-qtwebengine.list

    # Pinning: priorità 100 per tutto Debian (sotto Raspbian), ma 600 per Qt WebEngine
    sudo tee /etc/apt/preferences.d/debian-bookworm-qtwebengine > /dev/null << 'PINEOF'
# Repo Debian Bookworm aggiunto solo per Qt WebEngine (non disponibile in Raspbian armhf)
Package: *
Pin: origin deb.debian.org
Pin-Priority: 100

Package: qtwebengine5-dev libqt5webengine5 libqt5webenginecore5 libqt5webenginewidgets5 libqt5webengine-data qml-module-qtwebengine
Pin: origin deb.debian.org
Pin-Priority: 600
PINEOF

    sudo apt-get update
    info "Repository Debian Bookworm aggiunto con pinning selettivo."
fi

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
    "${QT_DBUS_PKG}" \
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
