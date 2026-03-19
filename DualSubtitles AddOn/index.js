'use strict';

const { addonBuilder, getRouter } = require('stremio-addon-sdk');
const express = require('express');
const manifest = require('./src/manifest');
const { createSubtitleHandler, getDualInfo, getLastUserConfig } = require('./src/subtitleHandler');
const { downloadSubtitle, guessFormatFromUrl, searchSubtitles, findBestMatch, findAllMatches } = require('./src/subtitleFetcher');

// Convert SRT content to ASS with custom styling
function srtToAss(srt, style) {
  const fs = style.fontSize || 20;
  // ASS colors: &HAABBGGRR — convert #RRGGBB hex
  function hexToAss(hex) {
    const h = hex.replace('#', '');
    const r = h.substring(0, 2), g = h.substring(2, 4), b = h.substring(4, 6);
    return '&H00' + b.toUpperCase() + g.toUpperCase() + r.toUpperCase();
  }
  const pc = hexToAss(style.color || 'FFFF00');
  const oc = hexToAss(style.borderColor || '000000');
  const bld = style.bold ? -1 : 0;
  const align = style.alignment || 8;

  let ass = '\uFEFF[Script Info]\n';
  ass += 'ScriptType: v4.00+\n';
  ass += 'PlayResX: 1920\n';
  ass += 'PlayResY: 1080\n';
  ass += 'WrapStyle: 0\n\n';
  ass += '[V4+ Styles]\n';
  ass += 'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n';
  ass += `Style: Default,DejaVu Sans,${fs},${pc},${pc},${oc},&H80000000,${bld},0,0,0,100,100,0,0,1,${style.borderSize || 2},0,${align},20,20,15,0\n\n`;
  ass += '[Events]\n';
  ass += 'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n';

  // Parse SRT blocks
  const blocks = srt.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim().split(/\n\n+/);
  for (const block of blocks) {
    const lines = block.split('\n');
    // Find the timestamp line (contains " --> ")
    let tsIdx = -1;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes(' --> ')) { tsIdx = i; break; }
    }
    if (tsIdx < 0) continue;
    const ts = lines[tsIdx].split(' --> ');
    if (ts.length < 2) continue;
    const start = srtTimeToAss(ts[0].trim());
    const end = srtTimeToAss(ts[1].trim());
    if (!start || !end) continue;
    // Join remaining lines as dialogue text, replace newlines with \N
    const text = lines.slice(tsIdx + 1).join('\\N').replace(/<[^>]*>/g, '');
    if (text) ass += `Dialogue: 0,${start},${end},Default,,0,0,0,,${text}\n`;
  }
  return ass;
}

// Convert SRT timestamp (HH:MM:SS,mmm) to ASS timestamp (H:MM:SS.cc)
function srtTimeToAss(t) {
  const m = t.match(/(\d+):(\d+):(\d+)[,\.](\d+)/);
  if (!m) return null;
  const h = parseInt(m[1]);
  const mm = m[2].padStart(2, '0');
  const ss = m[3].padStart(2, '0');
  const cs = m[4].substring(0, 3).padEnd(3, '0').substring(0, 2); // ms→centiseconds
  return `${h}:${mm}:${ss}.${cs}`;
}

const PORT = process.env.PORT || 7000;
const ADDON_URL = process.env.ADDON_URL || `http://127.0.0.1:${PORT}`;

// Track last dual activation for QML polling fallback
let lastDualActivation = null;

// Build the addon
const builder = new addonBuilder(manifest);
const subtitleHandler = createSubtitleHandler(ADDON_URL);
builder.defineSubtitlesHandler(subtitleHandler);
const addonInterface = builder.getInterface();

// Create Express app
const app = express();

// CORS + Cache-Control middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  res.header('Cache-Control', 'no-store, no-cache, must-revalidate');
  next();
});

// Request logger for debugging
app.use((req, res, next) => {
  console.log(`[DualSub] ${req.method} ${req.url}`);
  next();
});

// Dual info endpoint — shell queries this to get secondary subtitle URL + style
app.get('/dual-info/:videoKey', (req, res) => {
  const videoKey = req.params.videoKey;
  const info = getDualInfo(videoKey);
  if (!info) {
    return res.json({ found: false, videoKey });
  }
  res.json({
    found: true,
    videoKey,
    secondaryUrl: info.secondaryUrl,
    secondaryLang: info.secondaryLang,
    style: info.style,
  });
});

// Dual primary proxy — serves the primary subtitle through our server
// so the shell can detect the URL pattern (127.0.0.1:7000/dual-primary/)
// and automatically load the secondary via secondary-sid
app.get('/dual-primary/:videoKey', async (req, res) => {
  const videoKey = req.params.videoKey;
  console.log(`[DualSub] Dual-primary request for: ${videoKey}`);

  const info = getDualInfo(videoKey);
  if (!info || !info.primaryUrl) {
    console.log(`[DualSub] No primary cached for: ${videoKey}, serving empty subtitle`);
    // Serve empty subtitle so the track loads without error — user can pick languages from panel
    res.setHeader('Content-Type', 'application/x-subrip; charset=utf-8');
    return res.send('1\n00:00:00,000 --> 00:00:01,000\n \n');
  }

  // Record activation for QML polling fallback
  lastDualActivation = {
    videoKey,
    timestamp: Date.now(),
    secondaryUrl: info.secondaryUrl,
    secondaryLang: info.secondaryLang,
    style: info.style,
  };

  try {
    const content = await downloadSubtitle(info.primaryUrl);
    if (!content) {
      console.error(`[DualSub] Failed to download primary subtitle`);
      return res.status(502).send('Failed to download subtitle');
    }

    const format = guessFormatFromUrl(info.primaryUrl);
    const contentType = format === 'vtt' ? 'text/vtt' : 'application/x-subrip';
    const contentBuf = Buffer.from(content, 'utf8');
    res.setHeader('Content-Type', contentType + '; charset=utf-8');
    res.setHeader('Content-Length', contentBuf.length);
    console.log(`[DualSub] Serving primary subtitle (${contentBuf.length} bytes, ${format})`);
    res.end(contentBuf);
  } catch (err) {
    console.error('[DualSub] Error serving primary subtitle:', err);
    res.status(500).send('Error serving subtitle');
  }
});

// QML polling fallback: returns the latest dual activation info
// Used when QML cannot extract the videoKey from the web UI hash
app.get('/dual-latest', (req, res) => {
  if (lastDualActivation && (Date.now() - lastDualActivation.timestamp < 1800000)) {
    res.json({ active: true, ...lastDualActivation });
  } else {
    res.json({ active: false });
  }
});

// Styled subtitle proxy: converts SRT→ASS with custom styling for mpv secondary-sid
// (mpv 0.40 lacks secondary-sub-font-size/color/border properties)
app.get('/dual-styled-sub', async (req, res) => {
  const { url, fontSize, color, borderColor, borderSize, bold, alignment } = req.query;
  if (!url) return res.status(400).send('Missing url parameter');

  // Security: only allow HTTPS subtitle URLs
  if (!url.startsWith('https://')) {
    return res.status(403).send('Only HTTPS URLs allowed');
  }

  try {
    const content = await downloadSubtitle(url);
    if (!content) return res.status(502).send('Failed to download subtitle');

    const ass = srtToAss(content, {
      fontSize: parseInt(fontSize) || 20,
      color: (color || 'FFFF00'),
      borderColor: (borderColor || '000000'),
      borderSize: parseInt(borderSize) || 2,
      bold: bold === 'true' || bold === '1',
      alignment: parseInt(alignment) || 8, // 8 = top center
    });

    // Send as explicit UTF-8 Buffer to guarantee byte-level correctness
    const assBuf = Buffer.from(ass, 'utf8');
    res.setHeader('Content-Type', 'text/x-ssa; charset=utf-8');
    res.setHeader('Content-Length', assBuf.length);
    res.end(assBuf);
  } catch (err) {
    console.error('[DualSub] styled-sub error:', err);
    res.status(500).send('Conversion error');
  }
});

// Language-aware subtitle search: QML panel calls this when user changes languages
app.get('/dual-search/:type/:videoId', async (req, res) => {
  const { type, videoId } = req.params;
  const primaryLang = (req.query.primaryLang || 'ita').replace(/[^a-z]/g, '');
  const secondaryLang = (req.query.secondaryLang || 'eng').replace(/[^a-z]/g, '');
  const videoKey = videoId.replace(/[^a-zA-Z0-9_:-]/g, '');

  console.log(`[DualSub] dual-search: ${type}/${videoKey} primary=${primaryLang} secondary=${secondaryLang}`);
  try {
    const results = await searchSubtitles({ type, id: videoId });
    if (!results || results.length === 0) {
      return res.json({ found: false, videoKey, available: [] });
    }

    const primaryMatch = findBestMatch(results, primaryLang);
    const secondaryMatch = findBestMatch(results, secondaryLang);
    if (!secondaryMatch && !primaryMatch) {
      const langs = [...new Set(results.map(s => s.lang).filter(Boolean))];
      return res.json({ found: false, videoKey, available: langs });
    }

    const result = { found: true, videoKey };
    if (primaryMatch) { result.primaryUrl = primaryMatch.url; result.primaryLang = primaryLang; }
    if (secondaryMatch) { result.secondaryUrl = secondaryMatch.url; result.secondaryLang = secondaryLang; }

    // Return all variants per language for variant selection UI
    const primaryAll = findAllMatches(results, primaryLang);
    const secondaryAll = findAllMatches(results, secondaryLang);
    result.primaryVariants = primaryAll.map((s, i) => ({
      index: i, url: s.url, title: s.id || ('Variant ' + (i + 1))
    }));
    result.secondaryVariants = secondaryAll.map((s, i) => ({
      index: i, url: s.url, title: s.id || ('Variant ' + (i + 1))
    }));

    res.json(result);
  } catch (err) {
    console.error('[DualSub] dual-search error:', err);
    res.json({ found: false, videoKey, error: err.message });
  }
});

// On-demand dual subtitle fetch: QML calls this with type + videoId from the player hash.
// If cache is empty (e.g. after server restart), triggers a subtitle search to populate it.
app.get('/dual-fetch/:type/:videoId', async (req, res) => {
  const { type, videoId } = req.params;
  const videoKey = videoId.replace(/[^a-zA-Z0-9_:-]/g, '');

  // Check cache first
  let info = getDualInfo(videoKey);
  if (info) {
    console.log(`[DualSub] dual-fetch cache hit for ${videoKey} (secondaryUrl=${!!info.secondaryUrl})`);
    return res.json({
      found: !!info.secondaryUrl, videoKey,
      secondaryUrl: info.secondaryUrl || null,
      secondaryLang: info.secondaryLang,
      style: info.style,
      available: info.available || [],
    });
  }

  // Cache miss — trigger subtitle search using last known config (or defaults)
  console.log(`[DualSub] dual-fetch cache miss for ${videoKey}, searching...`);
  try {
    const userConfig = getLastUserConfig() || {};
    await subtitleHandler({ type, id: videoId, config: userConfig, extra: {} });
    info = getDualInfo(videoKey);
    if (info) {
      console.log(`[DualSub] dual-fetch search ${info.secondaryUrl ? 'succeeded' : 'partial'} for ${videoKey}`);
      return res.json({
        found: !!info.secondaryUrl, videoKey,
        secondaryUrl: info.secondaryUrl || null,
        secondaryLang: info.secondaryLang,
        style: info.style,
        available: info.available || [],
      });
    }
    console.log(`[DualSub] dual-fetch search found no subtitles at all for ${videoKey}`);
    res.json({ found: false, videoKey, available: [] });
  } catch (err) {
    console.error(`[DualSub] dual-fetch error:`, err);
    res.json({ found: false, videoKey, error: err.message });
  }
});

// Mount the stremio addon SDK router
app.use(getRouter(addonInterface));

// Start the server
const server = app.listen(PORT, () => {
  const url = `http://127.0.0.1:${PORT}/manifest.json`;
  console.log('HTTP addon accessible at:', url);
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║           🎬 Dual Subtitles Addon - Running!               ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Server:        http://127.0.0.1:${PORT}                       ║`);
  console.log(`║  Manifest:      ${url.padEnd(44)}║`);
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  Install in Stremio → Settings → Addons → paste this URL:  ║');
  console.log(`║  ${url.padEnd(61)}║`);
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  No API key required — uses Stremio community subtitles.   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
});
