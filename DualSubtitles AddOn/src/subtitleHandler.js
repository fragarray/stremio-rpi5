'use strict';

const { getConfig } = require('./config');
const { getMpvColor } = require('./colors');
const { generateAss } = require('./assGenerator');
const {
  searchSubtitles,
  downloadSubtitle,
  findBestMatch,
  extractImdbId,
} = require('./subtitleFetcher');
const Cache = require('./cache');

// Cache for generated/fetched subtitle files
const fileCache = new Cache(10 * 60 * 1000); // 10 minutes

/**
 * Create the subtitle handler function for the stremio addon.
 * @param {string} addonBaseUrl - The base URL of the addon server (e.g. http://localhost:7000)
 * @returns {Function} subtitleHandler(args) => Promise<{subtitles: Array}>
 */
function createSubtitleHandler(addonBaseUrl) {
  return async function subtitleHandler(args) {
    const { type, id, config: userConfig, extra } = args;

    const cfg = getConfig(userConfig);
    const imdbId = extractImdbId(id);
    if (!imdbId) {
      console.log(`[DualSub] No IMDb ID found in: ${id}`);
      return { subtitles: [] };
    }

    console.log(`[DualSub] Request: type=${type}, id=${id}, primary=${cfg.primaryLanguage}, secondary=${cfg.secondaryLanguage}`);

    // Query the community OpenSubtitles addon — uses standard Stremio addon protocol
    // The addon handles series IDs (tt1234567:1:2) natively, no need to filter
    const results = await searchSubtitles({ type, id });

    if (!results || results.length === 0) {
      console.log(`[DualSub] No subtitles found for ${id}`);
      return { subtitles: [] };
    }

    const filtered = results;

    // Find best match for each language
    const primaryMatch = findBestMatch(filtered, cfg.primaryLanguage);
    const secondaryMatch = findBestMatch(filtered, cfg.secondaryLanguage);

    const subtitles = [];

    // If we found BOTH languages, create the dual subtitle entries
    if (primaryMatch && secondaryMatch) {
      // Download both subtitle files directly from community addon URLs
      const [primaryContent, secondaryContent] = await Promise.all([
        downloadSubtitle(primaryMatch.url),
        downloadSubtitle(secondaryMatch.url),
      ]);

      if (primaryContent && secondaryContent) {
        // Generate ASS for primary with baked-in styles
        const primaryAss = generateAss(primaryContent, primaryMatch.format, {
          fontSize: cfg.primaryFontSize,
          color: cfg.primaryColor,
          outlineColor: cfg.primaryOutlineColor,
          outlineSize: cfg.primaryOutlineSize,
          bold: cfg.primaryBold,
          lang: cfg.primaryLanguage,
        });

        // Store in cache for serving via HTTP
        const videoKey = id.replace(/[^a-zA-Z0-9_:-]/g, '');
        fileCache.set(`primary:${videoKey}`, primaryAss);
        fileCache.set(`secondary:${videoKey}`, secondaryContent);
        fileCache.set(`secondaryFormat:${videoKey}`, secondaryMatch.format);

        // Build secondary style info for the shell
        const secondaryStyle = {
          fontSize: parseInt(cfg.secondaryFontSize, 10) * 2, // scale for readability
          color: getMpvColor(cfg.secondaryColor),
          outlineColor: getMpvColor(cfg.secondaryOutlineColor),
          outlineSize: parseInt(cfg.secondaryOutlineSize, 10),
          bold: cfg.secondaryBold === 'checked' || cfg.secondaryBold === true,
        };

        // URL-encode the style as a query parameter so the shell can read it
        const styleParam = encodeURIComponent(JSON.stringify(secondaryStyle));
        const secondaryExt = secondaryMatch.format === 'vtt' ? 'vtt' : 'srt';

        // Dual subtitle entries — the shell recognizes the "dual-" prefix
        subtitles.push({
          id: `dual-primary-${cfg.primaryLanguage}-${videoKey}`,
          url: `${addonBaseUrl}/subtitles/${encodeURIComponent(videoKey)}/primary.ass`,
          lang: `🔀 DUAL: ${cfg.primaryLanguage.toUpperCase()} (bottom) + ${cfg.secondaryLanguage.toUpperCase()} (top)`,
        });

        // The secondary URL includes style info and secondary URL for the shell to load
        subtitles.push({
          id: `dual-secondary-${cfg.secondaryLanguage}-${videoKey}`,
          url: `${addonBaseUrl}/subtitles/${encodeURIComponent(videoKey)}/secondary.${secondaryExt}?style=${styleParam}`,
          lang: `🔀 DUAL-SECONDARY: ${cfg.secondaryLanguage.toUpperCase()} (top) — select the DUAL entry above`,
        });
      }
    }

    // Also add individual subtitle entries for normal single-track use
    if (primaryMatch) {
      const videoKey = id.replace(/[^a-zA-Z0-9_:-]/g, '');
      subtitles.push({
        id: `single-${cfg.primaryLanguage}-${videoKey}`,
        url: `${addonBaseUrl}/subtitles/${encodeURIComponent(videoKey)}/primary.ass`,
        lang: `${cfg.primaryLanguage.toUpperCase()} (styled)`,
      });
    }

    console.log(`[DualSub] Returning ${subtitles.length} subtitle entries for ${imdbId}`);
    return { subtitles };
  };
}

/**
 * Get cached file content for serving.
 */
function getCachedFile(type, videoKey) {
  return fileCache.get(`${type}:${videoKey}`);
}

function getCachedSecondaryFormat(videoKey) {
  return fileCache.get(`secondaryFormat:${videoKey}`) || 'srt';
}

module.exports = { createSubtitleHandler, getCachedFile, getCachedSecondaryFormat };
