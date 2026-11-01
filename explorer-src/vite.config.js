import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { viteSingleFile } from 'vite-plugin-singlefile'

// stellar-trail explorer UI v5.0 — full miuix-vue migration (Task 53)
// Single-file build: the dist/index.html replaces assets/explorer/explorer-ui/index.html
// 1:1 — explorer.py's contract (GET / -> index.html, read per request) stays unchanged.
export default defineConfig({
  plugins: [vue(), viteSingleFile()],
  build: {
    target: 'es2018',
    minify: false,                 // v5.0: keep identifiers + byte markers greppable by the task11 regression validators
    cssCodeSplit: false,
    assetsInlineLimit: 100000000,
    chunkSizeWarningLimit: 100000,
    reportCompressedSize: false,
    outDir: 'dist'
  }
})
