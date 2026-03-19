'use strict';

const {
  LANGUAGE_OPTIONS,
  COLOR_OPTIONS,
  OUTLINE_COLOR_OPTIONS,
  FONT_SIZE_OPTIONS,
  OUTLINE_SIZE_OPTIONS,
} = require('./config');

const manifest = {
  id: 'community.dual-subtitles',
  version: '1.0.0',
  name: 'Dual Subtitles',
  description: 'Visualizza due tracce di sottotitoli contemporaneamente con controllo indipendente (delay, posizione, colore, dimensione). Usa le capacità native di mpv secondary-sid. Ideale per l\'apprendimento delle lingue.',
  logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/28/Subtitles_font_awesome.svg/200px-Subtitles_font_awesome.svg.png',
  resources: [
    { name: 'subtitles', types: ['movie', 'series'], idPrefixes: ['tt'] }
  ],
  types: ['movie', 'series'],
  catalogs: [],
  idPrefixes: ['tt'],
  behaviorHints: {
    configurable: true,
    configurationRequired: false,
  },
  config: [
    {
      key: 'primaryLanguage',
      type: 'select',
      title: 'Primary Language (Bottom)',
      options: LANGUAGE_OPTIONS,
      default: 'ita',
    },
    {
      key: 'secondaryLanguage',
      type: 'select',
      title: 'Secondary Language (Top)',
      options: LANGUAGE_OPTIONS,
      default: 'eng',
    },
    {
      key: 'primaryFontSize',
      type: 'select',
      title: 'Primary Font Size',
      options: FONT_SIZE_OPTIONS,
      default: '24',
    },
    {
      key: 'primaryColor',
      type: 'select',
      title: 'Primary Color',
      options: COLOR_OPTIONS,
      default: 'white',
    },
    {
      key: 'primaryOutlineColor',
      type: 'select',
      title: 'Primary Outline Color',
      options: OUTLINE_COLOR_OPTIONS,
      default: 'black',
    },
    {
      key: 'primaryOutlineSize',
      type: 'select',
      title: 'Primary Outline Size',
      options: OUTLINE_SIZE_OPTIONS,
      default: '2',
    },
    {
      key: 'primaryBold',
      type: 'checkbox',
      title: 'Primary Bold',
      default: 'checked',
    },
    {
      key: 'secondaryFontSize',
      type: 'select',
      title: 'Secondary Font Size',
      options: FONT_SIZE_OPTIONS,
      default: '20',
    },
    {
      key: 'secondaryColor',
      type: 'select',
      title: 'Secondary Color',
      options: COLOR_OPTIONS,
      default: 'yellow',
    },
    {
      key: 'secondaryOutlineColor',
      type: 'select',
      title: 'Secondary Outline Color',
      options: OUTLINE_COLOR_OPTIONS,
      default: 'black',
    },
    {
      key: 'secondaryOutlineSize',
      type: 'select',
      title: 'Secondary Outline Size',
      options: OUTLINE_SIZE_OPTIONS,
      default: '2',
    },
    {
      key: 'secondaryBold',
      type: 'checkbox',
      title: 'Secondary Bold',
    },
  ],
};

module.exports = manifest;
