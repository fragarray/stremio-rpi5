# 🎬 Stremio Dual Subtitles Addon

Visualizza **due tracce di sottotitoli contemporaneamente** in Stremio: una lingua in basso e una in alto, con controllo completamente indipendente per ciascuna traccia (delay, posizione, visibilità, colore, dimensione).

Ideale per l'**apprendimento delle lingue** — ad esempio, italiano in basso e inglese in alto.

## Come Funziona

Il sistema si compone di due parti:

1. **Addon Node.js** — Cerca e serve i sottotitoli da OpenSubtitles. Il sottotitolo primario viene convertito in formato ASS con gli stili selezionati dall'utente. Il secondario resta in SRT puro.

2. **Shell Enhancement** (già applicato in `main.qml`) — Usa la funzionalità nativa `secondary-sid` di mpv per caricare il secondo sottotitolo come traccia indipendente, con styling controllato dalle proprietà `sub-*` di mpv.

### Vantaggi rispetto al merge ASS
| Funzionalità | Merge ASS | Questo sistema (secondary-sid) |
|---|---|---|
| Due sottotitoli visibili | ✅ | ✅ |
| Delay indipendente a runtime | ❌ | ✅ |
| Toggle indipendente (mostra/nascondi) | ❌ | ✅ |
| Cambio lingua a runtime | ❌ | ✅ |
| Posizione indipendente | ❌ | ✅ |
| Stili indipendenti | Parziale | ✅ Completo |

## Requisiti

- **Node.js** >= 14 (hai già v20.19.4)
- **Stremio** con la shell modificata (main.qml con supporto dual subtitles — già applicato)
- **API Key OpenSubtitles** (gratuita) — opzionale ma raccomandata per risultati migliori

### Ottenere la API Key di OpenSubtitles (Gratuita)

1. Vai su https://www.opensubtitles.com/it e crea un account
2. Vai su https://www.opensubtitles.com/it/consumers e clicca "Create new consumer"
3. Compila il form (nome app: "DualSubtitles", descrizione: "Personal use")
4. Copia la API Key generata

## Installazione

### 1. Installa le dipendenze dell'addon

```bash
cd "/home/tom/stremio-shell-master/DualSubtitles AddOn"
npm install
```

### 2. Ricompila la Shell Stremio (già fatto)

Le modifiche a `main.qml` sono già applicate. Se devi ricompilare:

```bash
cd /home/tom/stremio-shell-master/build
cmake --build .
```

### 3. Avvia l'addon

```bash
cd "/home/tom/stremio-shell-master/DualSubtitles AddOn"
node index.js
```

Vedrai:
```
╔══════════════════════════════════════════════════════════════╗
║           🎬 Dual Subtitles Addon - Running!               ║
╠══════════════════════════════════════════════════════════════╣
║  Server:        http://127.0.0.1:7000                       ║
║  Manifest:      http://127.0.0.1:7000/manifest.json         ║
╚══════════════════════════════════════════════════════════════╝
```

### 4. Installa l'addon in Stremio

1. Apri **Stremio**
2. Vai in **Impostazioni** (⚙️) → **Addons**
3. Nel campo URL in alto, incolla: `http://127.0.0.1:7000/manifest.json`
4. Clicca **Install** / **Installa**

### 5. Configura l'addon

Dopo l'installazione, l'addon apparirà nella lista degli addons installati. Clicca su **Configura** per impostare:

- **Primary Language** — lingua del sottotitolo in basso (default: Italiano)
- **Secondary Language** — lingua del sottotitolo in alto (default: English)
- **Primary Font Size** — dimensione del primario (default: 24)
- **Primary Color** — colore del primario (default: white)
- **Secondary Font Size** — dimensione del secondario (default: 20)
- **Secondary Color** — colore del secondario (default: yellow)
- **OpenSubtitles API Key** — incolla qui la tua API key

## Utilizzo

### Uso Base

1. Assicurati che l'addon sia in esecuzione (`node index.js`)
2. Apri un **film** o **serie TV** in Stremio
3. Avvia la riproduzione
4. Clicca sull'icona dei **sottotitoli** (🅂) nel player
5. Nella lista vedrai le voci dell'addon:
   - `🔀 DUAL: ITA (bottom) + ENG (top)` ← **seleziona questa**
   - `🔀 DUAL-SECONDARY: ENG (top)` — informativa, non selezionare
   - `ITA (styled)` — sottotitolo singolo con stile personalizzato

6. Selezionando la voce DUAL:
   - Il sottotitolo **primario** (italiano) appare **in basso** con stile ASS
   - Il sottotitolo **secondario** (inglese) appare **in alto** con stile mpv (giallo di default)

### Controllo Indipendente a Runtime

Una volta attivo il modo duale, puoi usare la **console JavaScript** di Stremio o comandi mpv per controllare indipendentemente ciascun sottotitolo:

**Delay del primario:**
```
mpv-set-prop sub-delay 0.5       // ritarda di 0.5 secondi
mpv-set-prop sub-delay -0.3      // anticipa di 0.3 secondi
```

**Delay del secondario (INDIPENDENTE!):**
```
mpv-set-prop secondary-sub-delay 1.0    // ritarda di 1 secondo
mpv-set-prop secondary-sub-delay -0.5   // anticipa di 0.5 secondi
```

**Nascondere/mostrare il secondario:**
```
mpv-set-prop secondary-sub-visibility no    // nascondi
mpv-set-prop secondary-sub-visibility yes   // mostra
```

**Nascondere/mostrare il primario:**
```
mpv-set-prop sub-visibility no     // nascondi
mpv-set-prop sub-visibility yes    // mostra
```

**Posizione del secondario:**
```
mpv-set-prop secondary-sub-pos 10    // più in alto (0 = top)
mpv-set-prop secondary-sub-pos 30    // più in basso
```

## Struttura dei File

```
DualSubtitles AddOn/
├── package.json          # Dipendenze e script
├── index.js              # Entry point — avvia addon + server HTTP
├── .gitignore
├── README.md             # Questa guida
└── src/
    ├── manifest.js       # Manifest dell'addon con configurazione
    ├── subtitleHandler.js # Handler principale: cerca, scarica, genera
    ├── assGenerator.js   # Converte SRT/VTT → ASS con stile personalizzato
    ├── srtParser.js      # Parser SRT → cue array
    ├── vttParser.js      # Parser VTT → cue array
    ├── subtitleFetcher.js # Client API OpenSubtitles v2
    ├── cache.js          # Cache in-memory con TTL
    ├── config.js         # Validazione configurazione utente
    └── colors.js         # Mappatura colori → ASS e mpv
```

## Modifiche alla Shell

Il file `main.qml` è stato modificato per supportare i sottotitoli duali. Le modifiche includono:

- **Proprietà di stato**: `dualSubtitlesActive`, `dualSecondarySubUrl`, `dualSecondaryTrackId`, `dualSecondaryStyle`
- **Nuovi eventi transport**:
  - `dual-sub-enable` — carica secondario via `sub-add`, imposta `secondary-sid` e stili
  - `dual-sub-disable` — rimuove secondario e resetta stato
  - `secondary-sub-delay` — delay indipendente
  - `secondary-sub-toggle` — toggle visibilità
  - `secondary-sub-pos` — posizione indipendente
- **Observer `track-list`** — rileva quando mpv aggiunge la traccia secondaria e setta automaticamente `secondary-sid`

## Avvio Automatico (opzionale)

Per avviare l'addon automaticamente con il sistema:

### Systemd Service (Linux)

```bash
cat > ~/.config/systemd/user/dual-subtitles.service << 'EOF'
[Unit]
Description=Stremio Dual Subtitles Addon
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/tom/stremio-shell-master/DualSubtitles AddOn
ExecStart=/usr/bin/node index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user enable dual-subtitles
systemctl --user start dual-subtitles
```

## Risoluzione Problemi

### L'addon non trova sottotitoli
- Verifica che la tua API Key OpenSubtitles sia valida
- Prova con un film noto (es: un film Marvel) che ha molti sottotitoli
- Controlla i log nel terminale dove gira l'addon

### I sottotitoli duali non si attivano
- Assicurati di aver ricompilato la shell dopo le modifiche a `main.qml`
- Verifica che `./build/stremio` sia il binario aggiornato
- Controlla la console per messaggi `[DualSub]`

### Il secondario non appare
- mpv potrebbe non supportare `secondary-sid` su tutti i formati video
- Prova con un file video diverso
- Verifica che `sub-font-size` non sia troppo piccolo (controlla il log per i valori impostati)

### Porta 7000 già in uso
```bash
PORT=8000 node index.js
```
Ricordati di aggiornare l'URL del manifest in Stremio.

## Licenza

MIT
