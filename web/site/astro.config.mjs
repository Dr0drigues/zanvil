import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://dr0drigues.github.io',
  base: '/zanvil/',
  integrations: [
    starlight({
      title: 'zanvil',
      logo: { dark: './src/assets/logo-mark.svg', light: './src/assets/logo-mark-light.svg', alt: 'zanvil' },
      customCss: ['./src/styles/forge.css'],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/Dr0drigues/zanvil' },
      ],
      sidebar: [
        { label: 'Guides', items: [
          { label: 'Installation', slug: 'installation' },
          { label: 'Configuration', slug: 'configuration' },
          { label: 'Kubernetes et k9s', slug: 'kubernetes-k9s' },
        ]},
        { label: 'Référence', items: [
          { label: 'Commandes', slug: 'commandes' },
          { label: 'Tests', slug: 'tests' },
        ]},
      ],
    }),
  ],
});
