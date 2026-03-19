'use strict';

const { parseSrt, stripHtmlTags } = require('./srtParser');
const { parseVtt } = require('./vttParser');
const { getAssColor } = require('./colors');

/**
 * Generate an ASS (Advanced SubStation Alpha) file from subtitle text.
 * Used for the PRIMARY subtitle track — styles are baked into the file.
 * 
 * @param {string} subtitleText - Raw SRT or VTT text
 * @param {string} format - 'srt' or 'vtt'
 * @param {object} style - { fontSize, color, outlineColor, outlineSize, bold, lang }
 * @returns {string} ASS file content
 */
function generateAss(subtitleText, format, style) {
  const cues = format === 'vtt' ? parseVtt(subtitleText) : parseSrt(subtitleText);

  const fontSize = mapFontSize(style.fontSize || '24');
  const primaryColor = getAssColor(style.color || 'white');
  const outlineColor = getAssColor(style.outlineColor || 'black');
  const outlineSize = parseInt(style.outlineSize || '2', 10);
  const bold = (style.bold === 'checked' || style.bold === true) ? -1 : 0;
  const lang = (style.lang || 'Primary').toUpperCase();

  const header = `[Script Info]
Title: Dual Primary Subtitle - ${lang}
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes
`;

  const styles = `[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,${fontSize},${primaryColor},&H000000FF,${outlineColor},&H80000000,${bold},0,0,0,100,100,0,0,1,${outlineSize},1,2,20,20,60,1
`;

  let events = `[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n`;

  for (const cue of cues) {
    const text = escapeAssText(stripHtmlTags(cue.text));
    events += `Dialogue: 0,${cue.start},${cue.end},Default,,0,0,0,,${text}\n`;
  }

  return header + '\n' + styles + '\n' + events;
}

/**
 * Map user-facing font size to ASS PlayRes-relative font size.
 * PlayResY = 1080, so sizes are roughly doubled from "screen" size.
 */
function mapFontSize(sizeStr) {
  const size = parseInt(sizeStr, 10);
  // ASS font sizes at 1080p PlayRes: multiply by ~2 for readable size
  return Math.round(size * 2);
}

/**
 * Escape special ASS characters in subtitle text.
 * Newlines become \N, backslashes are handled, braces are preserved for potential override tags.
 */
function escapeAssText(text) {
  return text
    .replace(/\n/g, '\\N')
    .replace(/\r/g, '');
}

/**
 * Generate a merged ASS file with two subtitle tracks: primary (bottom) and secondary (top).
 * Both languages appear simultaneously in a single subtitle track.
 *
 * @param {string} primaryText - Raw SRT or VTT text for primary language
 * @param {string} secondaryText - Raw SRT or VTT text for secondary language
 * @param {string} primaryFormat - 'srt' or 'vtt'
 * @param {string} secondaryFormat - 'srt' or 'vtt'
 * @param {object} primaryStyle - { fontSize, color, outlineColor, outlineSize, bold, lang }
 * @param {object} secondaryStyle - { fontSize, color, outlineColor, outlineSize, bold, lang }
 * @returns {string} ASS file content with both languages
 */
function generateDualAss(primaryText, secondaryText, primaryFormat, secondaryFormat, primaryStyle, secondaryStyle) {
  const primaryCues = primaryFormat === 'vtt' ? parseVtt(primaryText) : parseSrt(primaryText);
  const secondaryCues = secondaryFormat === 'vtt' ? parseVtt(secondaryText) : parseSrt(secondaryText);

  const pFontSize = mapFontSize(primaryStyle.fontSize || '24');
  const pColor = getAssColor(primaryStyle.color || 'white');
  const pOutlineColor = getAssColor(primaryStyle.outlineColor || 'black');
  const pOutlineSize = parseInt(primaryStyle.outlineSize || '2', 10);
  const pBold = (primaryStyle.bold === 'checked' || primaryStyle.bold === true) ? -1 : 0;

  const sFontSize = mapFontSize(secondaryStyle.fontSize || '20');
  const sColor = getAssColor(secondaryStyle.color || 'yellow');
  const sOutlineColor = getAssColor(secondaryStyle.outlineColor || 'black');
  const sOutlineSize = parseInt(secondaryStyle.outlineSize || '2', 10);
  const sBold = (secondaryStyle.bold === 'checked' || secondaryStyle.bold === true) ? -1 : 0;

  const pLang = (primaryStyle.lang || 'Primary').toUpperCase();
  const sLang = (secondaryStyle.lang || 'Secondary').toUpperCase();

  const header = `[Script Info]
Title: Dual Subtitles - ${pLang} + ${sLang}
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes`;

  // Primary: Alignment 2 = bottom center, MarginV 60
  // Secondary: Alignment 8 = top center, MarginV 60
  const styles = `[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Primary,Arial,${pFontSize},${pColor},&H000000FF,${pOutlineColor},&H80000000,${pBold},0,0,0,100,100,0,0,1,${pOutlineSize},1,2,20,20,60,1
Style: Secondary,Arial,${sFontSize},${sColor},&H000000FF,${sOutlineColor},&H80000000,${sBold},0,0,0,100,100,0,0,1,${sOutlineSize},1,8,20,20,60,1`;

  let events = `[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n`;

  // Primary cues — add {\an2} override tag to ensure bottom positioning even if mpv overrides styles
  for (const cue of primaryCues) {
    const text = escapeAssText(stripHtmlTags(cue.text));
    events += `Dialogue: 0,${cue.start},${cue.end},Primary,,0,0,0,,{\\an2}${text}\n`;
  }

  // Secondary cues — add {\an8} override tag to force top positioning
  for (const cue of secondaryCues) {
    const text = escapeAssText(stripHtmlTags(cue.text));
    events += `Dialogue: 0,${cue.start},${cue.end},Secondary,,0,0,0,,{\\an8}${text}\n`;
  }

  return header + '\n' + styles + '\n' + events;
}

module.exports = { generateAss, generateDualAss, mapFontSize, escapeAssText };
