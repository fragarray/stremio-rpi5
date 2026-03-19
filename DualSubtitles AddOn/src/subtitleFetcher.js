'use strict';

const fetch = require('node-fetch');
const Cache = require('./cache');

// Stremio community OpenSubtitles addon — requires NO API key
const OPENSUBTITLES_ADDON = 'https://opensubtitles-v3.strem.io';

// Cache for search results (5 min) and downloaded files (10 min)
const searchCache = new Cache(5 * 60 * 1000);
const downloadCache = new Cache(10 * 60 * 1000);

/**
 * Query the Stremio community OpenSubtitles addon for subtitles.
 * Uses the standard Stremio addon protocol — NO API key required.
 *
 * @param {object} params - { type, id } where type is 'movie'|'series' and id is the Stremio video ID
 * @returns {Promise<Array>} Array of {id, url, lang} subtitle entries
 */
async function searchSubtitles({ type, id }) {
  const cacheKey = `search:${type}:${id}`;
  const cached = searchCache.get(cacheKey);
  if (cached) return cached;

  // Standard Stremio addon protocol: GET <addonUrl>/subtitles/<type>/<id>.json
  const url = `${OPENSUBTITLES_ADDON}/subtitles/${encodeURIComponent(type)}/${encodeURIComponent(id)}.json`;
  console.log(`[DualSub] Querying community addon: ${url}`);

  try {
    const response = await fetch(url, { timeout: 15000 });
    if (!response.ok) {
      console.error(`[DualSub] Community addon error: ${response.status} ${response.statusText}`);
      return [];
    }
    const data = await response.json();
    const results = data.subtitles || [];
    console.log(`[DualSub] Found ${results.length} subtitles from community addon`);
    searchCache.set(cacheKey, results);
    return results;
  } catch (err) {
    console.error(`[DualSub] Community addon query failed:`, err.message);
    return [];
  }
}

/**
 * Download a subtitle file from its URL.
 * The URLs come from the community addon and point to subs.strem.io — already UTF-8 encoded.
 *
 * @param {string} url - Direct URL to the subtitle file
 * @returns {Promise<string|null>} Subtitle file content or null on error
 */
async function downloadSubtitle(url) {
  const cacheKey = `download:${url}`;
  const cached = downloadCache.get(cacheKey);
  if (cached) return cached;

  try {
    console.log(`[DualSub] Downloading: ${url}`);
    const response = await fetch(url, { timeout: 15000 });
    if (!response.ok) {
      console.error(`[DualSub] Download error: ${response.status} ${response.statusText}`);
      return null;
    }
    const content = await response.text();
    downloadCache.set(cacheKey, content);
    return content;
  } catch (err) {
    console.error(`[DualSub] Download failed:`, err.message);
    return null;
  }
}

/**
 * Find the best subtitle match for a specific language from the community addon results.
 * The community addon returns: [{id, url, lang}, ...]
 * Returns the first match for the language (community addon already returns quality results).
 */
function findBestMatch(results, language) {
  const match = results.find(s => s.lang === language);
  if (!match) return null;
  return {
    id: match.id,
    url: match.url,
    lang: match.lang,
    format: guessFormatFromUrl(match.url),
  };
}

/**
 * Guess subtitle format from URL.
 */
function guessFormatFromUrl(url) {
  if (!url) return 'srt';
  const lower = url.toLowerCase();
  if (lower.includes('.vtt')) return 'vtt';
  if (lower.includes('.ass') || lower.includes('.ssa')) return 'ass';
  // The community addon typically serves SRT (auto-converted to UTF-8)
  return 'srt';
}

/**
 * Extract IMDb ID from Stremio video ID.
 * Stremio IDs: "tt1234567" (movie) or "tt1234567:1:2" (series S1E2)
 */
function extractImdbId(stremioId) {
  if (!stremioId) return null;
  const match = stremioId.match(/(tt\d+)/);
  return match ? match[1] : null;
}

module.exports = {
  searchSubtitles,
  downloadSubtitle,
  findBestMatch,
  guessFormatFromUrl,
  extractImdbId,
};
