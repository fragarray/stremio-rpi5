# Stremio for Raspberry Pi 5 (ARM64) — with Dual Subtitles

> **Community port** of [Stremio](https://www.stremio.com) for Raspberry Pi 5 and ARM64 single-board computers, featuring a powerful **Dual Subtitles** system for language learning and bilingual viewing.

Stremio is a modern media center that aggregates video content from multiple sources — movies, TV shows, series, live TV, and more. The official project only supports x86_64 Linux. **This fork brings full Stremio support to ARM64**, with native compilation, hardware-accelerated video decoding, a ready-to-install `.deb` package, and a deeply integrated **dual subtitle addon** that displays two subtitle tracks simultaneously with fully independent controls.

---

## Highlights

**Dual Subtitles** is the flagship feature of this fork. It allows you to display two subtitle languages at the same time — one at the bottom, one at the top — with independent style, delay, position, and visibility controls for each track. It is designed for **language learning**: watch a movie with your native language at the bottom and the language you're learning at the top, or vice versa.

This is not a simple overlay hack. The system uses mpv's native `secondary-sid` engine for rock-solid synchronization, while a dedicated Express server handles subtitle fetching, encoding detection, and ASS format conversion with custom styling. Every aspect — font size, color, border, bold, position — is independently adjustable per track, in real time, from a built-in settings panel.

---

## Features

### Core
- **Native ARM64 build** — compiled specifically for aarch64, no emulation
- **Hardware video decoding** — V4L2 M2M enabled by default for smooth playback on the RPi5 GPU
- **One-click install** — `.deb` package with automatic dependency resolution
- **Automatic server management** — the launcher starts the Node.js streaming server and the UI together
- **Full desktop integration** — application menu entry, icons, MIME type handlers
- **Fixes for modern mpv 0.40+** — patches deprecated mpv properties sent by the Stremio web UI

### Dual Subtitles
- **Two simultaneous subtitle tracks** — primary (bottom) + secondary (top), both visible during playback
- **30 supported languages** — Italian, English, Spanish, French, German, Portuguese, Japanese, Korean, Chinese, Arabic, Russian, Hindi, Polish, Turkish, Dutch, Swedish, Norwegian, Danish, Finnish, Czech, Romanian, Hungarian, Greek, Hebrew, Thai, Vietnamese, Indonesian, Malay, Brazilian Portuguese, Croatian, Slovenian
- **Independent style controls per track** — font size (10–120pt), 7 text colors, 5 border colors, border thickness (0–6px), bold toggle
- **Independent delay per track** — adjust timing ±0.1s per click, live update without reloading
- **Independent position** — place each track at top or bottom of the screen
- **Letterbox rendering** — optional toggle to render subtitles in the black bars outside the video frame
- **Multiple variants per language** — when multiple subtitle files exist for a language, browse them with a dot indicator and long-press selection
- **Smart encoding detection** — handles UTF-8, Windows-1252, UTF-16, and other encodings automatically, bypassing broken server-side conversions
- **Zero configuration** — no API key required, uses the Stremio community OpenSubtitles addon network
- **Auto-start** — the addon server launches automatically with Stremio, no manual startup needed
- **Persistent settings** — all style preferences are saved and restored across sessions

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

This will automatically install all required dependencies, including the Dual Subtitles addon. Then launch:

```bash
stremio
```

Or find **Stremio** in your application menu. The Dual Subtitles addon server starts automatically on port 7000.

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

# 2. Install the recommended subtitle font (full Unicode support)
sudo apt-get install -y fonts-dejavu-core

# 3. Clone and build
git clone --recurse-submodules https://github.com/AstraKernel/stremio-arm64.git
cd stremio-arm64

# 4. Install addon dependencies
cd "DualSubtitles AddOn"
npm install
cd ..

# 5. Build the .deb package
chmod +x scripts/build-deb.sh scripts/stremio-launcher.sh
bash scripts/build-deb.sh --compile

# 6. Install
sudo apt install ./stremio_4.4.181_arm64.deb
```

---

## Dual Subtitles — How It Works

The dual subtitle system is the core enhancement of this fork. It consists of three tightly integrated layers:

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Stremio Shell (Qt5/QML)                   │
│                                                             │
│  ┌───────────────┐   ┌──────────────────────────────────┐   │
│  │  Web UI        │   │  Dual Subtitle Panel (main.qml)  │   │
│  │  (Strem.io)    │◄──│  ● Language selection (30 langs)  │   │
│  │                │   │  ● Style controls per track       │   │
│  └───────┬────────┘   │  ● Delay / position / visibility  │   │
│          │            │  ● Letterbox toggle               │   │
│          ▼            │  ● Variant selector               │   │
│  ┌───────────────┐   └──────────┬───────────────────────┘   │
│  │  mpv Engine    │◄─────────────┘                           │
│  │  (libmpv)      │   sid + secondary-sid                    │
│  │                │   sub-ass-override = no                  │
│  │                │   sub-font = DejaVu Sans                 │
│  └───────┬────────┘                                          │
│          │ sub-add (ASS files via HTTP)                       │
└──────────┼──────────────────────────────────────────────────┘
           ▼
┌─────────────────────────────────────────────────────────────┐
│          Dual Subtitles Addon (Node.js / Express)           │
│          http://127.0.0.1:7000                              │
│                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ Subtitle     │  │  Encoding    │  │  ASS Generator    │  │
│  │ Fetcher      │  │  Detector    │  │  (SRT → ASS)      │  │
│  │              │  │              │  │                   │  │
│  │ Community    │  │ UTF-8 / BOM  │  │ DejaVu Sans font  │  │
│  │ OpenSubs API │  │ Win-1252     │  │ Custom colors     │  │
│  │ (no API key) │  │ UTF-16       │  │ 1920×1080 PlayRes │  │
│  └──────────────┘  └──────────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### The Three Layers

**1. Addon Server** (`DualSubtitles AddOn/`) — A Node.js Express server running on port 7000. It:
- Searches for subtitles via the Stremio community OpenSubtitles addon (no API key required)
- Downloads raw subtitle files, bypassing Stremio's broken server-side encoding conversion
- Detects encoding automatically (BOM → UTF-8 validation → Windows-1252 fallback)
- Converts SRT to ASS format with user-selected styling (font, color, border, alignment)
- Serves styled ASS files via HTTP for mpv to load

**2. Shell Integration** (`main.qml`) — Deep modifications to the Stremio Qt5/QML shell:
- A full settings panel ("Sottotitoli Duali") with independent controls for each track
- Automatic detection of dual subtitle selection via `localStorage` polling
- Track management: loads ASS files via `sub-add`, assigns `sid` and `secondary-sid`
- Blocks the web UI from overriding ASS styling (intercepts `sub-ass-override`, `no-sub-ass`)
- Persistent settings saved via Qt Settings (font sizes, colors, languages, etc.)

**3. mpv Configuration** (`mpv.cpp`) — Critical properties for correct rendering:
- `sub-ass-override=no` — preserves ASS font/color styling
- `sub-font=DejaVu Sans` — fallback font with full Unicode support (accented characters)
- `sub-codepage=utf-8` — forces UTF-8 subtitle decoding
- `sub-use-margins=yes` / `sub-ass-force-margins=yes` — enables letterbox rendering
- Blocks the deprecated `no-sub-ass` property that the web UI sends

### API Endpoints

The addon server exposes these endpoints:

| Endpoint | Purpose |
|----------|---------|
| `GET /manifest.json` | Stremio addon manifest for installation |
| `GET /dual-fetch/:type/:videoId` | Search and cache subtitles for a video |
| `GET /dual-search/:type/:videoId` | Search with explicit language parameters |
| `GET /dual-primary/:videoKey` | Download the primary subtitle (SRT) |
| `GET /dual-styled-sub?url=...&fontSize=...&color=...` | Download + convert to styled ASS |
| `GET /dual-info/:videoKey` | Get cached subtitle info for a video |
| `GET /dual-latest` | Fallback: get most recent activation info |

---

## Using Dual Subtitles

### First Time Setup

1. Launch Stremio — the addon server starts automatically
2. Go to **Settings** (⚙️) → **Addons**
3. Paste `http://127.0.0.1:7000/manifest.json` in the URL field
4. Click **Install**

### Watching with Dual Subtitles

1. Open a movie or TV show and start playback
2. Click the **subtitles icon** (🅂) in the player controls
3. Select **`🔀 DUAL: ITA (bottom) + ENG (top)`** (languages depend on your settings)
4. Both subtitle tracks appear: primary at the bottom, secondary at the top

### The Settings Panel

Press the **S₂** button (bottom-left corner, appears on mouse movement) to open the dual subtitle settings panel.

**Language Selection:**
- Two rows of language buttons — top row for primary, bottom row for secondary
- Tap to select a language; dot indicators show which variant is active
- Long-press a language to browse alternative subtitle files (variants)

**Style Controls (per track):**
- **Font size** — adjustable from 10pt to 120pt with ＋/－ buttons
- **Text color** — 7 options: yellow, white, green, cyan, orange, red, pink
- **Border color** — 5 options: black, white, gray, dark blue, dark red
- **Border size** — 0 to 6 pixels
- **Bold** — toggle on/off
- **Position** — "Alto" (top) or "Basso" (bottom)
- **Delay** — ±0.1 seconds per click

**Letterbox Toggle:**
- "Sottotitoli fuori video (letterbox)" — renders subtitles in the black bars outside the video frame, keeping the picture unobstructed

### Runtime Controls

With dual subtitles active, each track is fully independent. You can control them via mpv properties:

```
Primary subtitle:
  sub-delay        — timing offset (seconds)
  sub-visibility   — show/hide (yes/no)
  sub-pos          — vertical position (0–100)

Secondary subtitle:
  secondary-sub-delay      — timing offset (seconds)
  secondary-sub-visibility — show/hide (yes/no)
  secondary-sub-pos        — vertical position (0–100)
```

---

## How It Works (General)

Stremio consists of two main components:

1. **Streaming Server** (`server.js`) — a Node.js backend that handles content fetching, torrent streaming, transcoding, and addon management. It listens on `http://127.0.0.1:11470`.

2. **Shell UI** (`stremio`) — a Qt5/WebEngine application that loads the Stremio web interface and integrates a native mpv video player.

The **launcher script** (`stremio-launcher`) orchestrates everything:
- Checks if the streaming server is already running on port 11470
- If not, starts `node server.js` in the background
- Waits for the server to signal readiness (up to 120s on RPi)
- Launches the Stremio shell UI
- The DualSubtitles addon server starts automatically within the shell
- Cleans up all processes when the UI exits

---

## Changes from Upstream

This fork includes extensive modifications over the [official Stremio Shell](https://github.com/Stremio/stremio-shell):

### Dual Subtitles System (new)
- **Complete addon server** — Node.js/Express application in `DualSubtitles AddOn/` with subtitle search, download, encoding detection, and ASS conversion
- **QML settings panel** — ~700 lines of new UI code in `main.qml` with per-track controls, language selection, variant picker, letterbox toggle
- **mpv configuration** — `sub-ass-override=no`, `sub-font=DejaVu Sans`, `sub-codepage=utf-8` to preserve ASS styling and Unicode support
- **Web UI property filter** — blocks `sub-ass-override` and `no-sub-ass` from the web UI when dual subtitles are active, preventing style corruption
- **Smart encoding pipeline** — strips Stremio's broken `subencoding-stremio-utf8` server-side conversion, downloads raw bytes, auto-detects encoding (BOM → UTF-8 → Windows-1252)
- **Auto-start mechanism** — addon server spawns as a child process of the shell with automatic restart on failure

### ARM64 / Raspberry Pi 5 optimizations
- **Hardware decoding enabled by default** on ARM Linux (`hwdec=auto`) — uses the RPi5's V4L2 M2M HEVC/H.264 decoder
- Web UI's `hwdec=no` command is intercepted and overridden to keep hardware decoding active

### Fixes for modern mpv (0.40+)
- `vo=opengl-cb` → automatically translated to `vo=libmpv` (the old driver was removed)
- `cache-default` / `cache-backbuffer` → replaced with `demuxer-max-bytes` / `demuxer-max-back-bytes`
- `input-defalt-bindings` → typo corrected to `input-default-bindings`
- `no-sub-ass` → ignored entirely (was converting to `sub-ass-override=force`, breaking ASS styling)

### WebEngine initialization fix
- Added `QtWebEngine::initialize()` call before QML engine creation

### Packaging
- Debian package builder (`scripts/build-deb.sh`) for arm64
- Launcher script (`scripts/stremio-launcher.sh`) for automatic server + UI orchestration
- DualSubtitles addon bundled in the `.deb` package
- GitHub Actions CI/CD with automatic release publishing

---

## Project Structure

```
stremio-shell/
├── main.qml                    # QML UI — dual subtitle panel + mpv integration
├── mpv.cpp / mpv.h             # mpv engine — subtitle config, property handling
├── main.cpp                    # Application entry point
├── mainapplication.h           # Qt Application subclass
├── stremioprocess.cpp/h        # Streaming server process management
├── screensaver.cpp/h           # Screensaver inhibitor
├── systemtray.cpp/h            # System tray icon
├── autoupdater.cpp/h/js        # Auto-update mechanism
├── CMakeLists.txt              # Build configuration
│
├── DualSubtitles AddOn/        # ★ Dual subtitle addon server
│   ├── index.js                # Express server entry point, SRT→ASS converter
│   ├── package.json            # Node.js dependencies (express, node-fetch)
│   └── src/
│       ├── subtitleFetcher.js  # Download + encoding detection (UTF-8/Win-1252/UTF-16)
│       ├── subtitleHandler.js  # Search orchestration + response formatting
│       ├── manifest.js         # Stremio addon manifest definition
│       ├── assGenerator.js     # SRT/VTT → ASS format converter
│       ├── srtParser.js        # SRT subtitle parser
│       ├── vttParser.js        # WebVTT subtitle parser
│       ├── cache.js            # In-memory TTL cache
│       ├── config.js           # User configuration validation
│       └── colors.js           # Color mapping (hex → ASS, hex → mpv)
│
├── scripts/
│   ├── build-deb.sh            # Debian package builder (arm64)
│   ├── stremio-launcher.sh     # Server + UI launcher
│   ├── install-addon.sh        # Addon dependency installer
│   └── install-deps.sh         # Build dependency installer
│
├── deps/
│   ├── singleapplication/      # Single-instance application library
│   └── libmpv/                 # mpv development headers
│
├── CMakeModules/               # CMake find modules (FindMPV)
├── dist-utils/                 # Distribution packaging utilities
├── images/                     # Application icons (SVG + PNG)
└── scripts/                    # Build and deployment scripts
```

---

## Troubleshooting

### Dual Subtitles

**Subtitles not appearing:**
- Make sure the addon is running: look for `HTTP addon accessible at: http://127.0.0.1:7000/manifest.json` in the Stremio console output
- Verify the addon is installed in Stremio Settings → Addons
- Select a subtitle entry that starts with `🔀 DUAL:`

**Accented characters showing as `?`:**
- This is a known issue with Stremio's server-side encoding conversion (`subencoding-stremio-utf8`). The addon already bypasses this by downloading raw subtitle files and detecting encoding locally.
- Make sure the `fonts-dejavu-core` package is installed: `sudo apt install fonts-dejavu-core`
- If the issue persists, check the console log for encoding detection output: `[DualSub] Downloaded XXXXX bytes, encoding: windows-1252 (detected: windows-1252, header: none)` confirms the fix is active

**Settings panel not showing:**
- Move the mouse over the video — the S₂ button appears in the bottom-left corner after a brief delay

**Only one subtitle visible:**
- Some videos only have subtitles for one language. The secondary track will not appear if no matching subtitle is found.
- Try changing the secondary language from the settings panel.

### Video Playback

**Video stuttering / frame drops:**
The RPi5's GPU (VideoCore VII) cannot handle 4K HEVC decoding in software. Make sure hardware decoding is active:
- This build enables `hwdec=auto` by default
- If you still see `Using software decoding` in the logs, your content may use a codec not supported by the hardware decoder
- Try lower resolution streams (1080p works very well)

**"server-crash" error at startup:**
This means the Node.js streaming server failed to start. Check:
```bash
node /opt/stremio/server.js
```
Common causes:
- Port 11470 already in use (another Stremio instance?)
- Node.js not installed (`sudo apt install nodejs`)

**Black screen / WebEngine not loading:**
```bash
sudo apt install --fix-broken
```
If running under Wayland and experiencing issues:
```bash
QT_QPA_PLATFORM=xcb stremio
```

**No audio:**
```bash
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
| `nodejs` | Runs the streaming server and DualSubtitles addon |
| `libmpv2` | Video playback engine with `secondary-sid` support |
| `libqt5webengine5` | Chromium-based UI rendering |
| `libqt5webchannel5` | JavaScript ↔ C++ bridge |
| `qml-module-qtwebengine` | WebEngine QML integration |
| `qml-module-qtquick-controls` | UI controls |
| `qml-module-qtquick-dialogs` | File/error dialogs |
| `qml-module-qt-labs-platform` | Native platform dialogs |
| `fonts-dejavu-core` | DejaVu Sans font (full Unicode support for subtitles) |
| `librubberband2` | Audio time-stretching |
| `libuchardet0` | Character encoding detection |
| `libssl3` | TLS/HTTPS support |

---

## Technical Details

### Encoding Detection Pipeline

The subtitle encoding problem is one of the hardest challenges in this project. Many subtitle files on OpenSubtitles are encoded in Windows-1252 (Western European), not UTF-8. Stremio's server-side `subencoding-stremio-utf8` conversion often corrupts these files, turning accented characters (è, à, ñ, ü, ö) into `?`.

The solution implemented in `subtitleFetcher.js`:

1. **Strip server-side conversion** — remove `/subencoding-stremio-utf8/` from download URLs
2. **Download raw bytes** — use `ArrayBuffer` instead of `text()` to preserve original encoding
3. **BOM detection** — check for UTF-8/UTF-16 byte order marks
4. **UTF-8 validation** — attempt UTF-8 decode, check for replacement characters (`\uFFFD`)
5. **Windows-1252 fallback** — if UTF-8 fails, decode as Windows-1252
6. **ASS output** — always emit valid UTF-8 with BOM for maximum compatibility

### ASS Subtitle Format

The addon converts SRT subtitles to Advanced SubStation Alpha (ASS) format with:
- **Font:** DejaVu Sans (installed on all Debian/Ubuntu systems, full Unicode coverage)
- **PlayResX/PlayResY:** 1920×1080 (standard HD)
- **Color format:** `&H00BBGGRR` (ASS color encoding, converted from hex `#RRGGBB`)
- **Alignment:** 2 (bottom-center) for primary, 8 (top-center) for secondary
- **Encoding field:** 0 (ANSI/Western)
- **UTF-8 BOM:** prepended to every ASS output

### mpv Property Management

The Stremio web UI sends several mpv properties that would break dual subtitle rendering:

| Property sent by web UI | Problem | This fork's solution |
|------------------------|---------|---------------------|
| `no-sub-ass=true` | Converts to `sub-ass-override=force`, ignoring ASS styling | Ignored entirely in `mpv.cpp` |
| `sub-ass-override` | Overrides ASS fonts, colors, positioning | Blocked in QML when dual active |
| `hwdec=no` | Disables hardware decoding on ARM | Overridden to `hwdec=auto` |
| `vo=opengl-cb` | Deprecated mpv render API | Translated to `vo=libmpv` |

### Font Requirements

The subtitle system requires a font with full Unicode support for Western European accented characters. **DejaVu Sans** is the default because:
- Pre-installed on virtually all Debian/Ubuntu systems
- Complete coverage of Latin, Greek, Cyrillic, and extended character sets
- Available in Regular and Bold weights
- Resolved by fontconfig as the primary subtitle font

If Arial is not installed (common on headless/minimal systems), mpv's default font fallback may not support accented characters. This fork sets `sub-font=DejaVu Sans` in `mpv.cpp` to guarantee correct rendering.

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
- [OpenSubtitles](https://www.opensubtitles.com) — subtitle database (via Stremio community addon)
- [SingleApplication](https://github.com/itay-grudev/SingleApplication) — single-instance handler
- [DejaVu Fonts](https://dejavu-fonts.github.io/) — Unicode font used for subtitle rendering

## License

This project is based on the original Stremio Shell and maintains the same [MIT License](LICENSE.md).
