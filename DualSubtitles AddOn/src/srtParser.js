'use strict';

/**
 * Parse SRT subtitle text into an array of cue objects.
 * Handles both comma and dot as millisecond separator.
 * Returns: [{ start: "H:MM:SS.cc", end: "H:MM:SS.cc", text: "..." }, ...]
 *          where start/end are in ASS-compatible format.
 */
function parseSrt(srtText) {
  const cues = [];
  // Normalize line endings
  const text = srtText.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  // Split by double newline (cue blocks)
  const blocks = text.split(/\n\n+/).filter(b => b.trim());

  for (const block of blocks) {
    const lines = block.trim().split('\n');
    // Find the timestamp line (contains -->)
    let tsIdx = -1;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes('-->')) { tsIdx = i; break; }
    }
    if (tsIdx === -1) continue;

    const tsParts = lines[tsIdx].split('-->');
    if (tsParts.length < 2) continue;

    const start = parseSrtTimestamp(tsParts[0].trim());
    const end = parseSrtTimestamp(tsParts[1].trim());
    if (!start || !end) continue;

    // Text is everything after the timestamp line
    const cueText = lines.slice(tsIdx + 1).join('\n').trim();
    if (cueText) {
      cues.push({ start, end, text: cueText });
    }
  }
  return cues;
}

/**
 * Parse SRT timestamp "HH:MM:SS,mmm" or "HH:MM:SS.mmm"
 * Returns ASS format "H:MM:SS.cc" (centiseconds)
 */
function parseSrtTimestamp(ts) {
  // Remove any position tags (e.g. X1:123 X2:456...)
  ts = ts.replace(/\s+X\d+:\d+/gi, '').trim();
  const match = ts.match(/(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})/);
  if (!match) return null;

  const h = parseInt(match[1], 10);
  const m = match[2];
  const s = match[3];
  // Convert milliseconds to centiseconds
  let ms = match[4];
  while (ms.length < 3) ms += '0';
  const cs = Math.round(parseInt(ms, 10) / 10).toString().padStart(2, '0');

  return `${h}:${m}:${s}.${cs}`;
}

/**
 * Strip HTML-like tags from subtitle text (common in SRT files)
 */
function stripHtmlTags(text) {
  return text.replace(/<[^>]+>/g, '');
}

module.exports = { parseSrt, parseSrtTimestamp, stripHtmlTags };
