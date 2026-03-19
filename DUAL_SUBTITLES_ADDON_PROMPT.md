# Prompt: Stremio Dual Subtitles — Addon + Shell Enhancement

## Contesto e Obiettivo

Crea un sistema completo per Stremio che permetta di visualizzare **due tracce di sottotitoli contemporaneamente** sullo schermo: una posizionata in basso (lingua primaria) e una in alto (lingua secondaria). L'utente deve poter controllare **indipendentemente** ciascuna traccia: dimensione, colore, posizione, delay e visibilità.

Il progetto si compone di **due parti**:
1. **Stremio Addon** (server Node.js) — recupera e serve i sottotitoli
2. **Stremio Shell Enhancement** (modifica a main.qml) — abilita `secondary-sid` di mpv e il controllo indipendente dei due sottotitoli

## Perché NON il merge ASS

Un approccio alternativo sarebbe fondere due file sottotitolo in un unico file ASS con due stili. Questo funziona per la visualizzazione base, ma ha **limitazioni critiche**:
- **Nessun controllo indipendente del delay**: non puoi regolare il ritardo di una sola traccia a runtime
- **Nessun toggle indipendente**: non puoi nascondere/mostrare una sola traccia
- **Nessun cambio lingua a runtime**: per cambiare una delle due lingue, devi rigenerare l'intero file
- **Nessuna interazione con i controlli nativi di mpv** (sub-delay, sub-pos, ecc.)

Per questo motivo, il progetto usa le **capacità native di mpv** per i sottotitoli duali.

## Background Tecnico

### mpv — Supporto Nativo Sottotitoli Duali
mpv (libmpv 0.40.0) supporta nativamente la visualizzazione di due sottotitoli simultanei. Le proprietà chiave sono:

**Selezione tracce:**
- `sid` — seleziona la traccia sottotitolo primaria (visualizzata in basso)
- `secondary-sid` — seleziona la traccia sottotitolo secondaria (visualizzata in alto per default)

**Controllo indipendente del delay:**
- `sub-delay` — ritardo in secondi per il sottotitolo primario (positivo = ritarda, negativo = anticipa)
- `secondary-sub-delay` — ritardo in secondi per il sottotitolo secondario (indipendente dal primario)

**Controllo indipendente della posizione:**
- `sub-pos` — posizione verticale del primario (0-150, default 100 = basso)
- `secondary-sub-pos` — posizione verticale del secondario (0-150, default = alto)

**Controllo indipendente della visibilità:**
- `sub-visibility` — mostra/nascondi il primario (yes/no)
- `secondary-sub-visibility` — mostra/nascondi il secondario (yes/no)

**Override ASS:**
- `sub-ass-override` — default `scale`: rispetta gli stili ASS per il primario
- `secondary-sub-ass-override` — default `strip`: **RIMUOVE tutti i tag ASS** dal secondario, rendendolo testo puro

**Meccanismo di styling indipendente (FONDAMENTALE):**
Grazie al comportamento di `secondary-sub-ass-override=strip`, lo styling dei due sottotitoli è controllato da meccanismi diversi:
- **Primario**: se il file è in formato ASS, gli stili ASS embedded vengono rispettati (colore, font, dimensione, posizione sono definiti nel file ASS stesso). Le proprietà `sub-*` di mpv vengono in gran parte ignorate.
- **Secondario**: poiché ASS viene strippato, mpv usa le proprietà `sub-*` per lo styling: `sub-font-size`, `sub-color`, `sub-outline-color`, `sub-outline-size`, `sub-font`, `sub-bold`, ecc.

Questo permette di avere **stili completamente indipendenti**: il primario è controllato dagli stili ASS nel file, il secondario è controllato dalle proprietà mpv.

**Comandi per caricare sottotitoli esterni:**
- Comando mpv `sub-add <url> [flags [title [lang]]]` — aggiunge un file sottotitolo esterno come nuova traccia
- Comando mpv `sub-remove [id]` — rimuove una traccia sottotitolo

### Stremio Addon SDK
- Repository: https://github.com/Stremio/stremio-addon-sdk/tree/master
- L'addon è un server Node.js che espone un manifest JSON e gestisce richieste HTTP secondo il protocollo Stremio
- Le risorse disponibili sono: `catalog`, `meta`, `stream`, `subtitles`, `addon_catalog`
- Per i sottotitoli si usa `builder.defineSubtitlesHandler(function(args) { })` che riceve `{ type, id, extra: { videoHash, videoSize, filename }, config }` e ritorna `Promise<{ subtitles: [{ id, url, lang }] }>`
- Il formato Subtitle Object ha campi: `id` (string, univoco), `url` (string, URL al file sottotitolo), `lang` (string, codice ISO 639-2)
- Il manifest supporta `config` per le impostazioni utente con tipi: `text`, `number`, `password`, `checkbox`, `select`
- Il manifest supporta `behaviorHints.configurable: true` per abilitare la pagina `/configure`
- I sottotitoli vengono richiesti quando l'utente avvia uno stream; il `type` è il tipo di contenuto (movie, series), l'`id` è il videoId
- Il parametro `extra` contiene `videoHash` (hash OpenSubtitles), `videoSize` (dimensione file), `filename`

### Architettura dello Stremio Shell (Qt/QML + libmpv)
La shell Stremio è un'applicazione Qt/QML che integra libmpv come player video. La comunicazione tra UI web e mpv avviene tramite un layer di trasporto:

**File: main.qml — Transport layer**
```qml
QtObject {
    id: transport
    signal event(var ev, var args)
    function onEvent(ev, args) {
        if (ev === "mpv-command" && args && args[0] !== "run") mpv.command(args)
        if (ev === "mpv-set-prop") mpv.setProperty(args[0], args[1])
        if (ev === "mpv-observe-prop") mpv.observeProperty(args)
        // ... altri eventi
    }
}
```

**File: mpv.cpp — setProperty (NESSUN whitelist)**
```cpp
void MpvObject::setProperty(const QString& name, const QVariant& value) {
    // Fix per proprietà deprecate, poi passa QUALSIASI proprietà a mpv:
    mpv::qt::set_property(mpv, name, value);
}
```

**Implicazione chiave**: Stremio Shell passa QUALSIASI proprietà e comando a mpv senza whitelist. Questo significa che possiamo usare `secondary-sid`, `secondary-sub-delay`, `sub-font-size`, `sub-color` ecc. semplicemente aggiungendo nuovi eventi nel transport layer.

### Server locale Stremio
- Il server locale gira su `http://127.0.0.1:11470`
- Può fare proxy dei sottotitoli con encoding fix via `http://127.0.0.1:11470/subtitles.vtt?from=<url>`

## PARTE 1: Stremio Addon (Server Node.js)

### 1. Configurazione Utente (via manifest.config)
L'addon deve fornire una pagina di configurazione con questi parametri:

**Sorgente sottotitoli:**
- `primaryLanguage`: lingua della traccia primaria (select, es: "ita", "eng", "spa", "fra", "deu", "por", "jpn", "kor", "chi", "ara", "rus", "hin")
- `secondaryLanguage`: lingua della traccia secondaria (select, stesse opzioni)

**Stile traccia primaria (basso) — usato per generare il file ASS del primario:**
- `primaryFontSize`: dimensione font (select, default: "24", opzioni: "16"-"48")
- `primaryColor`: colore testo (select: "white", "yellow", "green", "cyan", "red", "magenta", "blue")
- `primaryBold`: grassetto (checkbox, default: checked)
- `primaryOutlineColor`: colore bordo/outline (select: "black", "dark-gray")
- `primaryOutlineSize`: spessore bordo (select, default: "2", range 0-5)

**Stile traccia secondaria (alto) — usato dalla shell per impostare le proprietà mpv `sub-*`:**
- `secondaryFontSize`: dimensione font (select, default: "20", opzioni: "16"-"48")
- `secondaryColor`: colore testo (select: "yellow" default, "white", "green", "cyan", ecc.)
- `secondaryBold`: grassetto (checkbox, default: off)
- `secondaryOutlineColor`: colore bordo/outline (select: "black", "dark-gray")
- `secondaryOutlineSize`: spessore bordo (select, default: "2", range 0-5)

- `opensubtitlesApiKey`: API key OpenSubtitles (text, opzionale)

### 2. Logica del Subtitle Handler
Quando Stremio richiede i sottotitoli per un video:

1. **Recuperare i sottotitoli disponibili** per il video dall'API di OpenSubtitles v2, utilizzando `videoHash`, `videoSize` e `imdbId` ricavato dall'`id` della richiesta
2. **Trovare il match** per `primaryLanguage` e `secondaryLanguage`
3. **Scaricare** entrambi i file (SRT o VTT)
4. **Per il primario**: convertire da SRT/VTT in **formato ASS** con gli stili della configurazione utente embedded nel file (colore, font, dimensione, outline, posizione basso con Alignment:2)
5. **Servire entrambi i file** tramite endpoint HTTP dell'addon
6. **Restituire a Stremio** una lista di sottotitoli che include:
   - Ogni singolo sottotitolo originale (per uso normale)
   - Il sottotitolo primario in formato ASS pre-stilizzato (ID speciale, es: `dual-primary-<lang>`)
   - Il sottotitolo secondario in formato originale (ID speciale, es: `dual-secondary-<lang>`)
   - Metadati nei subtitle ID che la shell può riconoscere (prefisso `dual-*`) per attivare il modo duale

### 3. Endpoint HTTP dell'Addon
L'addon espone:
- `/subtitles/:videoId/primary.ass` — file ASS con stile primary baked-in
- `/subtitles/:videoId/secondary.srt` — file SRT secondario (originale, senza styling — mpv lo stilizza via proprietà `sub-*`)
- Entrambi con CORS headers (`Access-Control-Allow-Origin: *`)
- Caching in-memory con TTL (5 minuti), chiave: `${videoId}:${lang}:${styleHash}`

### 4. Generazione del File ASS per il Primario
Il file ASS per il sottotitolo primario contiene UN SOLO stile (non merge) con configurazione utente:

```ass
[Script Info]
Title: Dual Primary Subtitle - ITA
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,1,2,20,20,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,Ciao, come stai?
```

**Note ASS:**
- Colori in formato `&HAABBGGRR` (Alpha, Blue, Green, Red — byte order inverso!)
- `Alignment: 2` = bottom-center (traccia primaria)
- Timing ASS usa `H:MM:SS.cc` (centesimi di secondo, NON millisecondi)
- `PlayResX/PlayResY`: 1920x1080 per consistenza
- `Fontsize` in ASS è relativo a PlayResY: mappare config value sensatamente (es: config 24 → ASS 48)

### 5. Mappatura Colori (Nome → ASS &HBBGGRR)
```javascript
const COLOR_MAP = {
  'white':   '&H00FFFFFF',
  'yellow':  '&H0000FFFF',
  'green':   '&H0000FF00',
  'cyan':    '&H00FFFF00',
  'red':     '&H000000FF',
  'magenta': '&H00FF00FF',
  'blue':    '&H00FF0000',
  'black':   '&H00000000',
  'dark-gray': '&H00404040',
};
```

### 6. Mappatura Colori (Nome → formato mpv `r/g/b`)
Per le proprietà mpv `sub-color`, `sub-outline-color` ecc., i colori sono in formato `r/g/b` (0.0-1.0) o `#RRGGBB`:
```javascript
const MPV_COLOR_MAP = {
  'white':   '#FFFFFF',
  'yellow':  '#FFFF00',
  'green':   '#00FF00',
  'cyan':    '#00FFFF',
  'red':     '#FF0000',
  'magenta': '#FF00FF',
  'blue':    '#0000FF',
  'black':   '#000000',
  'dark-gray': '#404040',
};
```

## PARTE 2: Stremio Shell Enhancement (Modifica a main.qml)

### Panoramica
La shell deve essere modificata per intercettare i sottotitoli "dual" provenienti dall'addon e attivare automaticamente il sistema `secondary-sid` di mpv. Le modifiche sono SOLO in main.qml (il layer di trasporto).

### Architettura della Shell Attuale
```
[Stremio Web UI] --WebChannel--> [Transport (main.qml)] --> [MpvObject (mpv.cpp)] --> [libmpv]
     |                                    |
     | "mpv-command"                      | mpv.command(args)
     | "mpv-set-prop"                     | mpv.setProperty(name, value)
     | "mpv-observe-prop"                 | mpv.observeProperty(name)
```

### Modifiche Necessarie a main.qml

**1. Nuove proprietà nel Transport:**
```qml
QtObject {
    id: transport
    // ... proprietà esistenti ...
    
    // Dual subtitles state
    property string secondarySubUrl: ""
    property int secondarySubTrackId: -1
    property bool dualSubtitlesActive: false
}
```

**2. Intercettare il caricamento sottotitoli dual:**
Quando la web UI carica un sottotitolo il cui URL contiene il path dell'addon dual subtitles (o quando viene inviato un evento specifico), la shell deve:

a) Riconoscere l'attivazione del modo duale (esempio: URL del sottotitolo contiene `/dual-primary/`)
b) Caricare il file secondario come traccia aggiuntiva via `sub-add`
c) Impostare `secondary-sid` alla traccia appena aggiunta
d) Applicare le proprietà di stile per il secondario

**3. Nuovo handler nel onEvent:**
```qml
function onEvent(ev, args) {
    // ... handler esistenti ...
    
    // Nuovo: attiva sottotitoli duali
    if (ev === "dual-sub-enable") {
        // args = { secondaryUrl: "http://...", style: { fontSize, color, outlineColor, outlineSize, bold } }
        var subAddCmd = ["sub-add", args.secondaryUrl, "auto", "Secondary"];
        mpv.command(subAddCmd);
        
        // Dopo che il sottotitolo è stato aggiunto, dobbiamo trovare il suo track ID
        // e impostare secondary-sid. Osserviamo track-list per rilevare la nuova traccia.
        transport.secondarySubUrl = args.secondaryUrl;
        transport.dualSubtitlesActive = true;
        
        // Applica stile per il sottotitolo secondario via proprietà sub-*
        // (queste proprietà vengono usate dal secondario perché secondary-sub-ass-override=strip)
        if (args.style) {
            mpv.setProperty("sub-font-size", args.style.fontSize || 38);
            mpv.setProperty("sub-color", args.style.color || "#FFFF00");
            mpv.setProperty("sub-outline-color", args.style.outlineColor || "#000000");
            mpv.setProperty("sub-outline-size", args.style.outlineSize || 2);
            mpv.setProperty("sub-bold", args.style.bold ? "yes" : "no");
        }
    }
    
    // Nuovo: disattiva sottotitoli duali
    if (ev === "dual-sub-disable") {
        mpv.setProperty("secondary-sid", "no");
        transport.dualSubtitlesActive = false;
    }
    
    // Nuovo: imposta delay del sottotitolo secondario (indipendente!)
    if (ev === "secondary-sub-delay") {
        mpv.setProperty("secondary-sub-delay", args); // valore in secondi
    }
    
    // Nuovo: toggle visibilità secondario (indipendente!)
    if (ev === "secondary-sub-toggle") {
        mpv.setProperty("secondary-sub-visibility", args ? "yes" : "no");
    }
}
```

**4. Rilevare il track ID del secondario:**
Dopo il comando `sub-add`, mpv aggiunge una nuova traccia alla `track-list`. Bisogna osservare il cambiamento e settare `secondary-sid`:

```qml
// Nella connessione mpvEvent:
MpvObject {
    id: mpv
    // ...
    onMpvEvent: function(ev, data) {
        // Handler esistente: inoltra a transport
        transport.event("mpv-event", JSON.stringify({ event: ev, args: data }));
        
        // Nuovo: quando track-list cambia e dual è attivo, trova e imposta secondary-sid
        if (ev === "mpv-prop-change" && data.name === "track-list" && transport.dualSubtitlesActive) {
            var tracks = data.data;
            if (Array.isArray(tracks)) {
                for (var i = 0; i < tracks.length; i++) {
                    if (tracks[i].type === "sub" && tracks[i]["external-filename"] &&
                        tracks[i]["external-filename"].indexOf("secondary") !== -1) {
                        mpv.setProperty("secondary-sid", tracks[i].id);
                        transport.secondarySubTrackId = tracks[i].id;
                        break;
                    }
                }
            }
        }
    }
}
```

**5. Aggiungere observe su track-list:**
Nella sezione di inizializzazione, aggiungere:
```qml
Component.onCompleted: {
    mpv.observeProperty("track-list");
}
```

### Proprietà mpv Riassuntive per il Controllo Indipendente
Queste proprietà possono essere impostate via `mpv.setProperty()` in qualsiasi momento a runtime:

| Proprietà | Tipo | Descrizione | Effetto |
|-----------|------|-------------|---------|
| `secondary-sid` | int/string | ID traccia secondario o "no" | Attiva/disattiva secondo sottotitolo |
| `secondary-sub-delay` | float | Secondi (+/-) | Ritardo indipendente del secondario |
| `secondary-sub-pos` | int (0-150) | Posizione verticale | Posizione indipendente del secondario |
| `secondary-sub-visibility` | string | "yes"/"no" | Toggle indipendente del secondario |
| `sub-delay` | float | Secondi (+/-) | Ritardo indipendente del primario |
| `sub-pos` | int (0-150) | Posizione verticale | Posizione indipendente del primario |
| `sub-visibility` | string | "yes"/"no" | Toggle indipendente del primario |
| `sub-font-size` | int | Dimensione font | Stile del secondario (il primario usa ASS) |
| `sub-color` | string | "#RRGGBB" o "#AARRGGBB" | Colore del secondario (il primario usa ASS) |
| `sub-outline-color` | string | "#RRGGBB" | Outline del secondario (il primario usa ASS) |
| `sub-outline-size` | float | Pixel scalati | Bordo del secondario (il primario usa ASS) |
| `sub-bold` | string | "yes"/"no" | Bold del secondario (il primario usa ASS) |
| `sub-font` | string | Nome font | Font del secondario (il primario usa ASS) |

## Specifiche Tecniche di Implementazione dell'Addon

### Stack Tecnologico
- **Runtime**: Node.js (>=14)
- **Framework addon**: `stremio-addon-sdk` (npm package)
- **HTTP server aggiuntivo**: Express.js (per servire i file ASS/SRT generati) — oppure usare `getRouter()` dell'SDK per integrarli
- **Parsing SRT/VTT**: libreria `subtitle` (npm) o parser custom
- **API sottotitoli**: OpenSubtitles REST API v2 (https://api.opensubtitles.com)
- **Caching**: cache in-memory (Map con TTL) per evitare download ripetuti

### Struttura del Progetto
```
stremio-dual-subtitles/
├── package.json
├── index.js              # Entry point, configura addon e server
├── src/
│   ├── manifest.js       # Definizione manifest con config
│   ├── subtitleHandler.js # Handler per defineSubtitlesHandler
│   ├── assGenerator.js   # Conversione SRT/VTT → ASS con stile personalizzato (per il primario)
│   ├── srtParser.js      # Parser SRT → struttura intermedia
│   ├── vttParser.js      # Parser VTT → struttura intermedia
│   ├── subtitleFetcher.js # Scarica sottotitoli da OpenSubtitles
│   ├── cache.js          # Cache in-memory con TTL
│   ├── config.js         # Validazione e default configurazione
│   └── colors.js         # Mappatura nomi colore → codici ASS e mpv
├── README.md
└── .gitignore
```

### OpenSubtitles API
- Endpoint REST v2: `https://api.opensubtitles.com/api/v1/subtitles`
- Richiede API key (gratuita con registrazione)
- Query parameters: `imdb_id`, `languages`, `moviehash`, `type`
- Risposta include `attributes.files[].file_id` per il download
- Download: `POST https://api.opensubtitles.com/api/v1/download` con `{ file_id }` → ritorna `{ link }` (URL temporaneo al file SRT)
- Alternativa senza API key: usare l'endpoint locale Stremio `http://127.0.0.1:11470/subtitles.vtt?from=<url>`

### Manifest Completo
```javascript
const manifest = {
  id: 'community.dual-subtitles',
  version: '1.0.0',
  name: 'Dual Subtitles',
  description: 'Visualizza due tracce di sottotitoli contemporaneamente con controllo indipendente (delay, posizione, colore, dimensione). Usa le capacità native di mpv secondary-sid. Ideale per l\'apprendimento delle lingue.',
  logo: 'https://i.imgur.com/URL_LOGO.png',
  resources: [
    { name: 'subtitles', types: ['movie', 'series'], idPrefixes: ['tt'] }
  ],
  types: ['movie', 'series'],
  catalogs: [],
  idPrefixes: ['tt'],
  behaviorHints: {
    configurable: true,
    configurationRequired: false
  },
  config: [
    { key: 'primaryLanguage', type: 'select', title: 'Primary Language (Bottom)', options: ['ita','eng','spa','fra','deu','por','jpn','kor','zho','ara','rus','hin','pol','tur','nld','swe','nor','dan','fin','ces','ron','hun','ell','heb','tha','vie','ind','msa'], default: 'ita' },
    { key: 'secondaryLanguage', type: 'select', title: 'Secondary Language (Top)', options: ['eng','ita','spa','fra','deu','por','jpn','kor','zho','ara','rus','hin','pol','tur','nld','swe','nor','dan','fin','ces','ron','hun','ell','heb','tha','vie','ind','msa'], default: 'eng' },
    { key: 'primaryFontSize', type: 'select', title: 'Primary Font Size', options: ['16','20','24','28','32','36','40','48'], default: '24' },
    { key: 'primaryColor', type: 'select', title: 'Primary Color', options: ['white','yellow','green','cyan','red','magenta','blue'], default: 'white' },
    { key: 'primaryOutlineColor', type: 'select', title: 'Primary Outline Color', options: ['black','dark-gray','white','yellow'], default: 'black' },
    { key: 'primaryOutlineSize', type: 'select', title: 'Primary Outline Size', options: ['0','1','2','3','4','5'], default: '2' },
    { key: 'primaryBold', type: 'checkbox', title: 'Primary Bold', default: 'checked' },
    { key: 'secondaryFontSize', type: 'select', title: 'Secondary Font Size', options: ['16','20','24','28','32','36','40','48'], default: '20' },
    { key: 'secondaryColor', type: 'select', title: 'Secondary Color', options: ['yellow','white','green','cyan','red','magenta','blue'], default: 'yellow' },
    { key: 'secondaryOutlineColor', type: 'select', title: 'Secondary Outline Color', options: ['black','dark-gray','white','yellow'], default: 'black' },
    { key: 'secondaryOutlineSize', type: 'select', title: 'Secondary Outline Size', options: ['0','1','2','3','4','5'], default: '2' },
    { key: 'secondaryBold', type: 'checkbox', title: 'Secondary Bold' },
    { key: 'opensubtitlesApiKey', type: 'text', title: 'OpenSubtitles API Key (get free at opensubtitles.com)', required: false }
  ]
};
```

## Requisiti Non Funzionali

1. **Performance**: usare cache in-memory con TTL (5 minuti) per i file generati. La chiave cache deve essere `${videoId}:${lang}:${styleHash}`
2. **Robustezza**: gestire gracefully errori di rete, sottotitoli non trovati, file malformati. Mai crashare il server.
3. **CORS**: tutti gli endpoint devono servire `Access-Control-Allow-Origin: *`
4. **Encoding**: gestire correttamente encoding UTF-8. Per sottotitoli con encoding sconosciuto, tentare auto-detect con `chardet` o libreria simile
5. **Compatibilità timing**: il parser SRT deve gestire sia il formato `HH:MM:SS,mmm` che `HH:MM:SS.mmm`. Il parser VTT deve gestire header WEBVTT e cue opzionali
6. **Logging**: log strutturato per debug (lingua richiesta, sottotitoli trovati, tracce caricate)
7. **Sicurezza**: validare e sanitizzare tutti gli input utente (config values). Non permettere path traversal o injection nei nomi file. Sanitizzare il testo dei sottotitoli prima di inserirlo nell'ASS (escape dei caratteri speciali ASS)
8. **Deploy**: deve funzionare sia localmente (`node index.js`) che su hosting (Heroku, Railway, Render, BeamUp). Rispettare la variabile d'ambiente `PORT`

## Flusso Operativo Completo

```
1. Utente configura addon (lingue, stili) → manifest.config salvato nell'URL addon

2. Utente avvia un video → Stremio chiede sottotitoli all'addon
                          → addon scarica SRT per primaryLang e secondaryLang
                          → addon converte primary SRT → ASS con stile embedded
                          → addon ritorna lista sottotitoli:
                            [
                              { id: "dual-primary-ita", url: "http://addon/subtitles/tt123/primary.ass", lang: "ita" },
                              { id: "dual-secondary-eng", url: "http://addon/subtitles/tt123/secondary.srt", lang: "eng" },
                              ... sottotitoli singoli originali ...
                            ]

3. Utente seleziona il sottotitolo primario "dual-primary-ita" → Stremio/shell carica il file ASS

4. La shell (main.qml) rileva il prefisso "dual-" e automaticamente:
   → carica il sottotitolo secondario via: mpv.command(["sub-add", secondaryUrl, "auto", "Secondary"])
   → osserva track-list e quando la nuova traccia appare:
     → mpv.setProperty("secondary-sid", trackId)
     → mpv.setProperty("sub-font-size", config.secondaryFontSize)
     → mpv.setProperty("sub-color", config.secondaryColor)
     → mpv.setProperty("sub-outline-color", config.secondaryOutlineColor)
     → mpv.setProperty("sub-outline-size", config.secondaryOutlineSize)
     → mpv.setProperty("sub-bold", config.secondaryBold ? "yes" : "no")

5. Risultato: DUE sottotitoli indipendenti sullo schermo
   - Primario (BASSO): stile controllato dal file ASS
   - Secondario (ALTO): stile controllato dalle proprietà sub-* di mpv

6. A runtime, l'utente può:
   - Regolare delay del primario: mpv.setProperty("sub-delay", valore)
   - Regolare delay del secondario: mpv.setProperty("secondary-sub-delay", valore)  ← INDIPENDENTE!
   - Nascondere il secondario: mpv.setProperty("secondary-sub-visibility", "no")
   - Spostare il secondario: mpv.setProperty("secondary-sub-pos", valore)
```

## Test e Validazione

1. Testare con un film noto (es: Big Buck Bunny, tt1254207) che ha sottotitoli su OpenSubtitles
2. Verificare che l'addon generi correttamente il file ASS primario e serva il SRT secondario
3. Verificare che la shell carichi automaticamente il secondario quando si seleziona un "dual-primary-*"
4. Verificare che i due sottotitoli appaiano contemporaneamente: il primario in basso, il secondario in alto
5. Verificare il **delay indipendente**: cambiare `secondary-sub-delay` senza influenzare `sub-delay` e viceversa
6. Verificare la **visibilità indipendente**: nascondere un sottotitolo senza influenzare l'altro
7. Verificare gli **stili indipendenti**: il primario deve usare lo stile ASS, il secondario deve usare le proprietà `sub-*`
8. Testare con serie TV (es: tt3107288:1:1) per validare il formato videoId delle serie
9. Testare il reset quando si cambia video o si disabilita il secondario

## Note Aggiuntive

### Vantaggio rispetto al merge ASS
| Funzionalità | Merge ASS | Native secondary-sid |
|---|---|---|
| Visualizzazione duale | ✅ | ✅ |
| Stili indipendenti | ✅ (via ASS styles) | ✅ (ASS primary + sub-* secondary) |
| Delay indipendente a runtime | ❌ | ✅ (`sub-delay` + `secondary-sub-delay`) |
| Toggle indipendente | ❌ | ✅ (`sub-visibility` + `secondary-sub-visibility`) |
| Cambio lingua a runtime | ❌ (rigenera file) | ✅ (cambia `secondary-sid`) |
| Posizione indipendente a runtime | ❌ | ✅ (`sub-pos` + `secondary-sub-pos`) |
| Nessuna modifica alla shell | ✅ | ❌ (richiede modifica main.qml) |

### Limitazioni note di `secondary-sid` in mpv
- I sottotitoli bitmap (DVD, Bluray/PGS) vengono sempre renderizzati nella loro posizione originale — possibile sovrapposizione
- Lo styling ASS viene completamente strippato dalla traccia secondaria (`secondary-sub-ass-override=strip` è il default). Per questo il primario va fornito come ASS styled, e il secondario viene stilizzato via proprietà `sub-*`
- Se il primario contiene tag ASS che posizionano il testo in alto (es: `\an8`), potrebbe sovrapporsi al secondario. Per evitarlo, il file ASS primario deve sempre usare `Alignment: 2` (bottom-center)

### Tips per l'apprendimento delle lingue
- Lingua madre in basso (primario): testo grande, bianco, ben leggibile
- Lingua che si sta imparando in alto (secondario): testo più piccolo, giallo, complementare
- Usare `secondary-sub-delay` per sincronizzare manualmente se il timing è leggermente sfasato

### Info sul sistema target
- Stremio Shell v4.4.181, Qt 5.15.17, libmpv 0.40.0
- Ubuntu 25.10 (Questing Quokka), Raspberry Pi 5 8GB, ARM64
- Node.js 20.19.4
- La shell è già modificata per il supporto ARM64 (hwdec auto, proprietà deprecate rimate)
