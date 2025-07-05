import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://MKS2508.github.io',
  base: '/MKS-IPTV-App',
  output: 'static',
  
  integrations: [
    tailwind({
      applyBaseStyles: false,
    }),
    sitemap(),
  ],

  vite: {
    optimizeDeps: {
      include: ['gsap', 'lenis', '@tsparticles/engine'],
    },
    build: {
      cssMinify: true,
      minify: 'esbuild',
      rollupOptions: {
        output: {
          assetFileNames: 'assets/[name].[hash][extname]',
          chunkFileNames: 'assets/[name].[hash].js',
          entryFileNames: 'assets/[name].[hash].js',
        },
      },
    },
  },

  build: {
    assets: 'assets',
  },
});
