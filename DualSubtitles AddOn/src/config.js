'use strict';

// Language codes as used by the Stremio community OpenSubtitles addon
// NOTE: these are OpenSubtitles codes, NOT ISO 639-2 (e.g. 'fre' not 'fra', 'ger' not 'deu', 'cze' not 'ces')
const LANGUAGE_OPTIONS = [
  'ita', 'eng', 'spa', 'fre', 'ger', 'por', 'jpn', 'kor', 'chi',
  'ara', 'rus', 'hin', 'pol', 'tur', 'dut', 'swe', 'nor', 'dan',
  'fin', 'cze', 'ron', 'hun', 'ell', 'heb', 'tha', 'vie', 'ind', 'may',
  'pob', 'hrv', 'slv'
];

const COLOR_OPTIONS = ['white', 'yellow', 'green', 'cyan', 'red', 'magenta', 'blue'];
const OUTLINE_COLOR_OPTIONS = ['black', 'dark-gray', 'white', 'yellow'];
const FONT_SIZE_OPTIONS = ['16', '20', '24', '28', '32', '36', '40', '48'];
const OUTLINE_SIZE_OPTIONS = ['0', '1', '2', '3', '4', '5'];

const DEFAULTS = {
  primaryLanguage: 'ita',
  secondaryLanguage: 'eng',
  primaryFontSize: '24',
  primaryColor: 'white',
  primaryOutlineColor: 'black',
  primaryOutlineSize: '2',
  primaryBold: 'checked',
  secondaryFontSize: '20',
  secondaryColor: 'yellow',
  secondaryOutlineColor: 'black',
  secondaryOutlineSize: '2',
  secondaryBold: '',
};

function getConfig(userConfig) {
  const cfg = {};
  for (const key of Object.keys(DEFAULTS)) {
    cfg[key] = (userConfig && userConfig[key] != null && userConfig[key] !== '')
      ? userConfig[key]
      : DEFAULTS[key];
  }
  // Validate languages
  if (!LANGUAGE_OPTIONS.includes(cfg.primaryLanguage)) cfg.primaryLanguage = DEFAULTS.primaryLanguage;
  if (!LANGUAGE_OPTIONS.includes(cfg.secondaryLanguage)) cfg.secondaryLanguage = DEFAULTS.secondaryLanguage;
  // Validate colors
  if (!COLOR_OPTIONS.includes(cfg.primaryColor)) cfg.primaryColor = DEFAULTS.primaryColor;
  if (!COLOR_OPTIONS.includes(cfg.secondaryColor)) cfg.secondaryColor = DEFAULTS.secondaryColor;
  if (!OUTLINE_COLOR_OPTIONS.includes(cfg.primaryOutlineColor)) cfg.primaryOutlineColor = DEFAULTS.primaryOutlineColor;
  if (!OUTLINE_COLOR_OPTIONS.includes(cfg.secondaryOutlineColor)) cfg.secondaryOutlineColor = DEFAULTS.secondaryOutlineColor;
  // Validate numeric strings
  if (!FONT_SIZE_OPTIONS.includes(cfg.primaryFontSize)) cfg.primaryFontSize = DEFAULTS.primaryFontSize;
  if (!FONT_SIZE_OPTIONS.includes(cfg.secondaryFontSize)) cfg.secondaryFontSize = DEFAULTS.secondaryFontSize;
  if (!OUTLINE_SIZE_OPTIONS.includes(cfg.primaryOutlineSize)) cfg.primaryOutlineSize = DEFAULTS.primaryOutlineSize;
  if (!OUTLINE_SIZE_OPTIONS.includes(cfg.secondaryOutlineSize)) cfg.secondaryOutlineSize = DEFAULTS.secondaryOutlineSize;
  return cfg;
}

module.exports = {
  LANGUAGE_OPTIONS,
  COLOR_OPTIONS,
  OUTLINE_COLOR_OPTIONS,
  FONT_SIZE_OPTIONS,
  OUTLINE_SIZE_OPTIONS,
  DEFAULTS,
  getConfig,
};
