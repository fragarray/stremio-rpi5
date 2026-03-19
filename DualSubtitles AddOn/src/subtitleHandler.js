'use strict';

const { getConfig } = require('./config');
const { getMpvColor } = require('./colors');
const {
  searchSubtitles,
  downloadSubtitle,
  findBestMatch,
  extractImdbId,
} = require('./subtitleFetcher');
const Cache = require('./cache');

// Cache for dual info (secondary URL + style), keyed by videoKey
const dualInfoCache = new Cache(30 * 60 * 1000); // 30 minutes

// Store last-used user config so /dual-fetch/ can reuse it
let lastUserConfig = null;

/**
 * Create the subtitle handler function for the stremio addon.
 * @param {string} addonBaseUrl - The base URL of the addon server (e.g. http://localhost:7000)
 * @returns {Function} subtitleHandler(args) => Promise<{subtitles: Array}>
 */
function createSubtitleHandler(addonBaseUrl) {
  return async function subtitleHandler(args) {
    const { type, id, config: userConfig, extra } = args;

    const cfg = getConfig(userConfig);
    lastUserConfig = cfg;
    const imdbId = extractImdbId(id);
    if (!imdbId) {
      console.log(`[DualSub] No IMDb ID found in: ${id}`);
      return { subtitles: [] };
    }

    console.log(`[DualSub] Request: type=${type}, id=${id}, primary=${cfg.primaryLanguage}, secondary=${cfg.secondaryLanguage}`);

    // Query the community OpenSubtitles addon — uses standard Stremio addon protocol
    const results = await searchSubtitles({ type, id });

    if (!results || results.length === 0) {
      console.log(`[DualSub] No subtitles found for ${id}`);
      return { subtitles: [] };
    }

    // Find best match for each language
    const primaryMatch = findBestMatch(results, cfg.primaryLanguage);
    const secondaryMatch = findBestMatch(results, cfg.secondaryLanguage);

    const subtitles = [];
    const videoKey = id.replace(/[^a-zA-Z0-9_:-]/g, '');

    // Build mpv-compatible style for the secondary subtitle
    const secondaryStyle = {
      fontSize: parseInt(cfg.secondaryFontSize, 10),
      color: getMpvColor(cfg.secondaryColor),
      borderColor: getMpvColor(cfg.secondaryOutlineColor),
      borderSize: parseInt(cfg.secondaryOutlineSize, 10),
      bold: cfg.secondaryBold === 'checked' || cfg.secondaryBold === true,
    };

    // Collect available languages for the panel
    const availableLangs = [...new Set(results.map(s => s.lang).filter(Boolean))];

    // Cache whatever we found (may be partial — null URLs are OK)
    dualInfoCache.set(videoKey, {
      primaryUrl: primaryMatch ? primaryMatch.url : null,
      secondaryUrl: secondaryMatch ? secondaryMatch.url : null,
      secondaryLang: cfg.secondaryLanguage,
      style: secondaryStyle,
      available: availableLangs,
    });

    // Always create the DUAL entry when any subtitles exist
    const dualEntry = {
      id: `dual-${cfg.primaryLanguage}-${cfg.secondaryLanguage}-${videoKey}`,
      url: `${addonBaseUrl}/dual-primary/${encodeURIComponent(videoKey)}`,
      lang: 'DUAL SUBTITLES',
    };
    subtitles.push(dualEntry);

    // Also add individual subtitle entries — pass through original objects
    if (primaryMatch) {
      const singlePrimary = Object.assign({}, primaryMatch, {
        id: `dsub-${primaryMatch.id}-${cfg.primaryLanguage}`,
      });
      subtitles.push(singlePrimary);
    }
    if (secondaryMatch && (!primaryMatch || cfg.primaryLanguage !== cfg.secondaryLanguage)) {
      const singleSecondary = Object.assign({}, secondaryMatch, {
        id: `dsub-${secondaryMatch.id}-${cfg.secondaryLanguage}`,
      });
      subtitles.push(singleSecondary);
    }

    console.log(`[DualSub] Returning ${subtitles.length} subtitle entries for ${imdbId}`);
    return { subtitles, cacheMaxAge: 0 };
  };
}

/**
 * Get cached dual info for a videoKey.
 * If exact match fails, tries prefix match (e.g. tt32420734 matches tt32420734:1:2)
 */
function getDualInfo(videoKey) {
  const exact = dualInfoCache.get(videoKey);
  if (exact) return exact;

  // Prefix match: the shell may only have the IMDb ID without episode numbers
  for (const [key] of dualInfoCache._store) {
    if (key.startsWith(videoKey)) {
      const val = dualInfoCache.get(key);
      if (val) {
        console.log(`[DualSub] Prefix match: '${videoKey}' → '${key}'`);
        return val;
      }
    }
  }
  return null;
}

module.exports = { createSubtitleHandler, getDualInfo, getLastUserConfig: () => lastUserConfig };
