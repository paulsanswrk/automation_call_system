import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'

const now = new Date()
const buildVersion = `${now.getUTCFullYear()}${(now.getUTCMonth()+1).toString().padStart(2,'0')}${now.getUTCDate().toString().padStart(2,'0')}.${now.getUTCHours().toString().padStart(2,'0')}${now.getUTCMinutes().toString().padStart(2,'0')}`

export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(buildVersion)
  },
  plugins: [
    vue(),
    VitePWA({
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'prompt',
      includeAssets: ['favicon.svg', 'icon-192.png', 'icon-512.png'],
      manifest: {
        name: 'ACT Trading',
        short_name: 'ACT',
        description: 'Algorithmic Crypto Trading Dashboard',
        theme_color: '#0f172a',
        background_color: '#0f172a',
        display: 'standalone',
        start_url: '/',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      injectManifest: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
      },
    }),
  ],
  resolve: {
    alias: {
      '@': '/src',
    },
  },
})
