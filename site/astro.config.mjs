import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://dr0drigues.github.io',
  base: '/zsh_env/',
  integrations: [
    starlight({
      title: 'zanvil',
      logo: { src: './src/assets/logo-mark.svg', alt: 'zanvil' },
      customCss: ['./src/styles/forge.css'],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/Dr0drigues/zsh_env' },
      ],
      sidebar: [
        { label: 'Guides', items: [
          { label: 'Installation', slug: 'installation' },
          { label: 'Configuration', slug: 'configuration' },
        ]},
        { label: 'Référence', items: [
          { label: 'Commandes', slug: 'commandes' },
        ]},
      ],
    }),
  ],
});
