'use strict';

/**
 * Parse VTT (WebVTT) subtitle text into an array of cue objects.
 * Returns: [{ start: "H:MM:SS.cc", end: "H:MM:SS.cc", text: "..." }, ...]
 *          where start/end are in ASS-compatible format.
 */
function parseVtt(vttText) {
  const cues = [];
  // Normalize line endings
  const text = vttText.replace(/\r\n/g, '\n').replace(/\r/g, '\n');

  // Remove WEBVTT header and any metadata before first cue
  const lines = text.split('\n');
  let startIdx = 0;
  // Skip header line and optional metadata
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('-->')) { startIdx = i; break; }
    // Also skip NOTE blocks and STYLE blocks
  }

  const body = lines.slice(startIdx).join('\n');
  // Split by double newline
  const blocks = body.split(/\n\n+/).filter(b => b.trim());

  for (const block of blocks) {
    const blines = block.trim().split('\n');
    // Find timestamp line
    let tsIdx = -1;
    for (let i = 0; i < blines.length; i++) {
      if (blines[i].includes('-->')) { tsIdx = i; break; }
    }
    if (tsIdx === -1) continue;

    const tsParts = blines[tsIdx].split('-->');
    if (tsParts.length < 2) continue;

    const start = parseVttTimestamp(tsParts[0].trim());
    const end = parseVttTimestamp(tsParts[1].trim().split(/\s+/)[0]); // remove positioning info after timestamp
    if (!start || !end) continue;

    const cueText = blines.slice(tsIdx + 1).join('\n').trim();
    if (cueText) {
      cues.push({ start, end, text: cueText });
    }
  }
  return cues;
}

/**
 * Parse VTT timestamp "HH:MM:SS.mmm" or "MM:SS.mmm"
 * Returns ASS format "H:MM:SS.cc" (centiseconds)
 */
function parseVttTimestamp(ts) {
  ts = ts.trim();
  // VTT can be MM:SS.mmm or HH:MM:SS.mmm
  let match = ts.match(/^(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,3})/);
  if (!match) {
    // Try MM:SS.mmm format
    match = ts.match(/^(\d{2}):(\d{2})\.(\d{1,3})/);
    if (!match) return null;
    const m = match[1];
    const s = match[2];
    let ms = match[3];
    while (ms.length < 3) ms += '0';
    const cs = Math.round(parseInt(ms, 10) / 10).toString().padStart(2, '0');
    return `0:${m}:${s}.${cs}`;
  }

  const h = parseInt(match[1], 10);
  const m = match[2];
  const s = match[3];
  let ms = match[4];
  while (ms.length < 3) ms += '0';
  const cs = Math.round(parseInt(ms, 10) / 10).toString().padStart(2, '0');
  return `${h}:${m}:${s}.${cs}`;
}

module.exports = { parseVtt, parseVttTimestamp };
