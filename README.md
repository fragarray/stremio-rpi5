# Stremio for Raspberry Pi 5 (ARM64)

> **Community port** of [Stremio](https://www.stremio.com) for Raspberry Pi 5 and ARM64 single-board computers running Ubuntu/Debian.

Stremio is a modern media center that aggregates video content from multiple sources — movies, TV shows, series, live TV, and more. The official project only supports x86_64 Linux. **This fork brings full Stremio support to ARM64**, with native compilation, hardware-accelerated video decoding, and a ready-to-install `.deb` package.

---

## Features

- **Native ARM64 build** — compiled specifically for aarch64, no emulation
- **Hardware video decoding** — V4L2 M2M enabled by default for smooth playback on the RPi5 GPU
- **One-click install** — `.deb` package with automatic dependency resolution
- **Automatic server management** — the launcher starts the Node.js streaming server and the UI together
- **Full desktop integration** — application menu entry, icons, MIME type handlers (magnet links, torrent files, video files)
- **Fixes for modern mpv 0.40+** — patches deprecated mpv properties sent by the Stremio web UI

## Target Hardware

| Board | RAM | Status |
|-------|-----|--------|
| Raspberry Pi 5 | 8 GB | **Fully tested** |
| Raspberry Pi 5 | 4 GB | Should work (WebEngine is memory-hungry) |
| Other ARM64 SBCs | 4+ GB | Should work if running Ubuntu/Debian arm64 |

**Recommended OS:** Ubuntu 24.04+ or Debian Bookworm+ (arm64)

---

## Installation

### From the .deb package (recommended)

Download the latest `.deb` from the [Releases](../../releases) page, then:

```bash
sudo apt install ./stremio_4.4.181_arm64.deb
```

This will automatically install all required dependencies. Then launch:

```bash
stremio
```

Or find **Stremio** in your application menu.

### From source

```bash
# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake pkgconf librsvg2-bin wget git \
  libssl-dev libmpv-dev \
  qtbase5-dev qtdeclarative5-dev qtwebengine5-dev \
  libqt5opengl5-dev libqt5webchannel5-dev \
  qml-module-qtwebchannel qml-module-qtwebengine \
  qml-module-qt-labs-platform qml-module-qtquick-dialogs \
  qml-module-qtquick-controls qml-module-qt-labs-settings \
  qml-module-qt-labs-folderlistmodel \
  nodejs

# 2. Clone and build
git clone --recurse-submodules https://github.com/AstraKernel/stremio-arm64.git
cd stremio-arm64

# 3. Build the .deb package
chmod +x scripts/build-deb.sh scripts/stremio-launcher.sh
bash scripts/build-deb.sh --compile

# 4. Install
sudo apt install ./stremio_4.4.181_arm64.deb
```

---

## How It Works

Stremio consists of two components:

1. **Streaming Server** (`server.js`) — a Node.js backend that handles content fetching, torrent streaming, transcoding, and addon management. It listens on `http://127.0.0.1:11470`.

2. **Shell UI** (`stremio`) — a Qt5/WebEngine application that loads the Stremio web interface and integrates a native mpv video player.

The **launcher script** (`stremio-launcher`) orchestrates both:
- Checks if the server is already running on port 11470
- If not, starts `node server.js` in the background
- Waits for the server to signal readiness
- Launches the Stremio shell UI
- Cleans up the server process when the UI exits

---

## Changes from Upstream

This fork includes the following modifications over the [official Stremio Shell](https://github.com/Stremio/stremio-shell):

### ARM64 / Raspberry Pi 5 optimizations
- **Hardware decoding enabled by default** on ARM Linux (`hwdec=auto`) — uses the RPi5's V4L2 M2M HEVC/H.264 decoder
- Web UI's `hwdec=no` command is intercepted and overridden to keep hardware decoding active

### Fixes for modern mpv (0.40+)
- `vo=opengl-cb` → automatically translated to `vo=libmpv` (the old driver was removed)
- `cache-default` / `cache-backbuffer` → replaced with `demuxer-max-bytes` / `demuxer-max-back-bytes`
- `input-defalt-bindings` → typo corrected to `input-default-bindings`
- `no-sub-ass` → translated to modern `sub-ass-override`

### WebEngine initialization fix
- Added `QtWebEngine::initialize()` call before QML engine creation (fixes `WebEngineContext used before QtWebEngine::initialize()`)

### Packaging
- Debian package builder (`scripts/build-deb.sh`) for arm64
- Launcher script (`scripts/stremio-launcher.sh`) for automatic server + UI orchestration
- GitHub Actions CI/CD with automatic release publishing

---

## Troubleshooting

### Video stuttering / frame drops
The RPi5's GPU (VideoCore VII) cannot handle 4K HEVC decoding in software. Make sure hardware decoding is active:
- This build enables `hwdec=auto` by default
- If you still see `Using software decoding` in the logs, your content may use a codec not supported by the hardware decoder
- Try lower resolution streams (1080p works very well)

### "server-crash" error at startup
This means the Node.js streaming server failed to start. Check:
```bash
# Test the server manually:
node /opt/stremio/server.js
```
Common causes:
- Port 11470 already in use (another Stremio instance?)
- Node.js not installed (`sudo apt install nodejs`)
- Corrupted server.js (re-download: `wget https://dl.strem.io/server/v4.20.16/desktop/server.js -O /opt/stremio/server.js`)

### Black screen / WebEngine not loading
```bash
# Check if all Qt/QML modules are installed:
sudo apt install --fix-broken
```
If running under Wayland and experiencing issues, try:
```bash
QT_QPA_PLATFORM=xcb stremio
```

### No audio
Stremio uses PipeWire/PulseAudio. Make sure your audio system is set up:
```bash
# Check PipeWire status
systemctl --user status pipewire
```

### Uninstall
```bash
sudo apt remove stremio
# To also remove configuration:
sudo apt purge stremio
```

---

## Runtime Dependencies

All dependencies are installed automatically by `apt` when installing the `.deb`:

| Package | Purpose |
|---------|---------|
| `nodejs` | Runs the streaming server backend |
| `libmpv2` | Video playback engine |
| `libqt5webengine5` | Chromium-based UI rendering |
| `libqt5webchannel5` | JavaScript ↔ C++ bridge |
| `qml-module-qtwebengine` | WebEngine QML integration |
| `qml-module-qtquick-controls` | UI controls |
| `qml-module-qtquick-dialogs` | File/error dialogs |
| `qml-module-qt-labs-platform` | Native platform dialogs |
| `librubberband2` | Audio time-stretching |
| `libuchardet0` | Character encoding detection |
| `libssl3` | TLS/HTTPS support |

---

## CI/CD

The GitHub Actions workflow (`.github/workflows/build-and-release.yml`) handles:

- **On push to main/master**: builds the `.deb` and uploads it as an artifact
- **On tag push (`v*`)**: builds the `.deb` and creates a GitHub Release with the `.deb` file directly downloadable

### Creating a new release
```bash
git tag v4.4.181
git push origin v4.4.181
```

---

## Credits

- [Stremio](https://www.stremio.com) — the original media center by Smart Code Ltd
- [stremio-shell](https://github.com/Stremio/stremio-shell) — upstream Qt5 shell
- [mpv](https://mpv.io) — video player engine
- [SingleApplication](https://github.com/itay-grudev/SingleApplication) — single-instance handler

## License

This project is based on the original Stremio Shell and maintains the same [MIT License](LICENSE.md).
