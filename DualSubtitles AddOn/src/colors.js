'use strict';

// ASS color format: &HAABBGGRR (Alpha, Blue, Green, Red — reversed byte order!)
const ASS_COLOR_MAP = {
  'white':     '&H00FFFFFF',
  'yellow':    '&H0000FFFF',
  'green':     '&H0000FF00',
  'cyan':      '&H00FFFF00',
  'red':       '&H000000FF',
  'magenta':   '&H00FF00FF',
  'blue':      '&H00FF0000',
  'black':     '&H00000000',
  'dark-gray': '&H00404040',
};

// mpv sub-color format: #RRGGBB
const MPV_COLOR_MAP = {
  'white':     '#FFFFFF',
  'yellow':    '#FFFF00',
  'green':     '#00FF00',
  'cyan':      '#00FFFF',
  'red':       '#FF0000',
  'magenta':   '#FF00FF',
  'blue':      '#0000FF',
  'black':     '#000000',
  'dark-gray': '#404040',
};

function getAssColor(name) {
  return ASS_COLOR_MAP[name] || ASS_COLOR_MAP['white'];
}

function getMpvColor(name) {
  return MPV_COLOR_MAP[name] || MPV_COLOR_MAP['white'];
}

module.exports = { ASS_COLOR_MAP, MPV_COLOR_MAP, getAssColor, getMpvColor };
