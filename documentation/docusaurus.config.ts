import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Fairest One',
  tagline: 'Journal de conception du miroir connecté',
  favicon: 'img/favicon.png',
  future: {v4: true},
  url: 'https://sabsab93.github.io',
  baseUrl: '/Fairest-One/',
  organizationName: 'SabSab93',
  projectName: 'Fairest-One',
  onBrokenLinks: 'throw',
  i18n: {
    defaultLocale: 'fr',
    locales: ['fr'],
  },
  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: 'construction',
          editUrl:
            'https://github.com/SabSab93/Fairest-One/edit/feature/docusaurus-build-journal/documentation/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],
  themeConfig: {
    metadata: [
      {
        name: 'keywords',
        content: 'Fairest One, miroir connecté, IoT, ESP32, impression 3D',
      },
    ],
    colorMode: {
      defaultMode: 'light',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'FAIREST ONE',
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'buildJournal',
          position: 'left',
          label: 'Journal de fabrication',
        },
        {
          href: 'https://github.com/SabSab93/Fairest-One',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'light',
      links: [],
      copyright: `Fairest One · Journal de conception · ${new Date().getFullYear()}`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.github,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
