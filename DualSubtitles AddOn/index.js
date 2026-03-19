'use strict';

const { addonBuilder, getRouter } = require('stremio-addon-sdk');
const express = require('express');
const manifest = require('./src/manifest');
const { createSubtitleHandler, getCachedFile, getCachedSecondaryFormat } = require('./src/subtitleHandler');

const PORT = process.env.PORT || 7000;

// Determine the base URL for the addon
// In production, set ADDON_URL env variable (e.g., https://your-addon.herokuapp.com)
// Locally, we use localhost
const ADDON_URL = process.env.ADDON_URL || `http://127.0.0.1:${PORT}`;

// Build the addon
const builder = new addonBuilder(manifest);

// Create the subtitle handler with the addon base URL
const subtitleHandler = createSubtitleHandler(ADDON_URL);
builder.defineSubtitlesHandler(subtitleHandler);

// Get the addon interface
const addonInterface = builder.getInterface();

// Create Express app — custom routes FIRST, then SDK router
const app = express();

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  next();
});

// Serve generated subtitle files (MUST be before SDK router to avoid path conflicts)
app.get('/subtitles/:videoKey/primary.ass', (req, res) => {
  const videoKey = req.params.videoKey;
  const content = getCachedFile('primary', videoKey);
  if (!content) {
    console.log(`[DualSub] Primary subtitle not found in cache for: ${videoKey}`);
    return res.status(404).send('Subtitle not found. Try playing the video again to trigger subtitle fetch.');
  }
  res.setHeader('Content-Type', 'text/x-ssa; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="primary.ass"');
  res.send(content);
});

app.get('/subtitles/:videoKey/secondary.srt', (req, res) => {
  const videoKey = req.params.videoKey;
  const content = getCachedFile('secondary', videoKey);
  if (!content) {
    console.log(`[DualSub] Secondary subtitle not found in cache for: ${videoKey}`);
    return res.status(404).send('Subtitle not found. Try playing the video again to trigger subtitle fetch.');
  }
  res.setHeader('Content-Type', 'application/x-subrip; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="secondary.srt"');
  res.send(content);
});

app.get('/subtitles/:videoKey/secondary.vtt', (req, res) => {
  const videoKey = req.params.videoKey;
  const content = getCachedFile('secondary', videoKey);
  if (!content) {
    console.log(`[DualSub] Secondary subtitle not found in cache for: ${videoKey}`);
    return res.status(404).send('Subtitle not found. Try playing the video again to trigger subtitle fetch.');
  }
  res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="secondary.vtt"');
  res.send(content);
});

// Info endpoint
app.get('/dual-info/:videoKey', (req, res) => {
  const videoKey = req.params.videoKey;
  const hasPrimary = !!getCachedFile('primary', videoKey);
  const hasSecondary = !!getCachedFile('secondary', videoKey);
  const secondaryFormat = getCachedSecondaryFormat(videoKey);
  res.json({
    videoKey,
    hasPrimary,
    hasSecondary,
    secondaryFormat,
    secondaryUrl: hasSecondary
      ? `${ADDON_URL}/subtitles/${encodeURIComponent(videoKey)}/secondary.${secondaryFormat}`
      : null,
  });
});

// Mount the stremio addon SDK router AFTER custom routes
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
  console.log('║  Configure languages and styles from the addon settings.   ║');
  console.log('║  No API key required — uses Stremio community subtitles.   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
});
