import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  buildJournal: [
    'introduction',
    {
      type: 'category',
      label: '01 · Cadrer',
      collapsed: false,
      items: ['idee-et-inspirations', 'bom'],
    },
    {
      type: 'category',
      label: '02 · Concevoir',
      collapsed: false,
      items: [
        'releves-dimensionnels',
        'esquisses-papier',
        'conception-fusion',
        'pieces-3d',
      ],
    },
    {
      type: 'category',
      label: '03 · Fabriquer',
      collapsed: false,
      items: [
        'impression-3d',
        'electronique-arduino',
        'montage-final',
      ],
    },
  ],
};

export default sidebars;
