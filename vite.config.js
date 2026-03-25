import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    port: 3000,
    headers: {
      // Required for WebAssembly SharedArrayBuffer or proper loading sometimes
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    }
  },
  build: {
    outDir: 'dist',
    target: 'esnext'
  }
});
