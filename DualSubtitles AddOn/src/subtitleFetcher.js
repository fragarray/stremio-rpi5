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
 * Extract charset from Content-Type header, e.g. "text/plain; charset=iso-8859-1" → "iso-8859-1"
 */
function extractCharset(contentType) {
  if (!contentType) return null;
  const m = contentType.match(/charset\s*=\s*([\w-]+)/i);
  return m ? m[1].toLowerCase() : null;
}

/**
 * Detect encoding from raw bytes: check BOM, then try UTF-8 validation.
 * Returns the encoding label suitable for TextDecoder.
 */
function detectEncoding(buf) {
  const bytes = new Uint8Array(buf);
  // UTF-8 BOM
  if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) return 'utf-8';
  // UTF-16 LE BOM
  if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) return 'utf-16le';
  // UTF-16 BE BOM
  if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) return 'utf-16be';

  // Try decoding as UTF-8 — if replacement characters appear, it's not valid UTF-8
  const trial = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  if (!trial.includes('\uFFFD')) return 'utf-8';

  // Fallback: Windows-1252 covers most Western European accented characters
  return 'windows-1252';
}

/**
 * Download a subtitle file from its URL.
 * Handles encoding detection: checks HTTP Content-Type charset, BOM, and UTF-8 validity.
 * Falls back to Windows-1252 for files with accented characters that aren't valid UTF-8.
 *
 * @param {string} url - Direct URL to the subtitle file
 * @returns {Promise<string|null>} Subtitle file content (always valid UTF-8 string) or null on error
 */
async function downloadSubtitle(url) {
  const cacheKey = `download:${url}`;
  const cached = downloadCache.get(cacheKey);
  if (cached) return cached;

  // Strip Stremio's broken server-side encoding conversion — we handle encoding ourselves
  const rawUrl = url.replace(/\/subencoding-stremio-utf8\//, '/');

  try {
    console.log(`[DualSub] Downloading: ${rawUrl}`);
    const response = await fetch(rawUrl, { timeout: 15000 });
    if (!response.ok) {
      console.error(`[DualSub] Download error: ${response.status} ${response.statusText}`);
      return null;
    }

    // Read raw bytes to handle encoding properly
    const buf = await response.arrayBuffer();

    // Determine encoding: auto-detect from bytes (most reliable), fall back to HTTP header
    const headerCharset = extractCharset(response.headers.get('content-type'));
    const detectedEncoding = detectEncoding(buf);
    const encoding = detectedEncoding;

    const content = new TextDecoder(encoding, { fatal: false }).decode(buf);
    console.log(`[DualSub] Downloaded ${buf.byteLength} bytes, encoding: ${encoding} (detected: ${detectedEncoding}, header: ${headerCharset || 'none'})`);

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
  // Return the FULL original object — the web UI may depend on extra fields
  return Object.assign({}, match);
}

/**
 * Find ALL subtitle matches for a specific language.
 * Returns an array of {id, url, lang, SubFileName, ...} objects.
 */
function findAllMatches(results, language) {
  return results.filter(s => s.lang === language).map(s => Object.assign({}, s));
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
  findAllMatches,
  guessFormatFromUrl,
  extractImdbId,
};
