import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import electron from 'vite-plugin-electron'
import renderer from 'vite-plugin-electron-renderer'
import { resolve } from 'path'

const now = new Date()
const buildVersion = `${now.getUTCFullYear()}${(now.getUTCMonth()+1).toString().padStart(2,'0')}${now.getUTCDate().toString().padStart(2,'0')}.${now.getUTCHours().toString().padStart(2,'0')}${now.getUTCMinutes().toString().padStart(2,'0')}`

export default defineConfig({
  root: 'src/renderer',
  envDir: resolve(__dirname),
  define: {
    __APP_VERSION__: JSON.stringify(buildVersion),
  },
  plugins: [
    vue(),
    electron([
      {
        entry: resolve(__dirname, 'src/main/index.ts'),
        onstart(args) {
          args.startup()
        },
        vite: {
          build: {
            outDir: resolve(__dirname, 'dist-electron/main'),
            rollupOptions: {
              external: ['electron', 'electron-store'],
            },
          },
        },
      },
      {
        entry: resolve(__dirname, 'src/main/preload.ts'),
        onstart(args) {
          args.reload()
        },
        vite: {
          build: {
            outDir: resolve(__dirname, 'dist-electron/preload'),
            rollupOptions: {
              external: ['electron'],
            },
          },
        },
      },
    ]),
    renderer(),
  ],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src/renderer'),
    },
  },
  build: {
    outDir: resolve(__dirname, 'dist'),
    emptyOutDir: true,
  },
})
