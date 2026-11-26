import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

// The built app is committed into backend/public/app and served by the
// backend (routes/webAppRoutes.js): Cloud Run's image is built from backend/
// alone, by whichever session runs deploy.sh. Assets load from /public/app/.
export default defineConfig(({ command }) => ({
  plugins: [react()],
  // Built files load from /public/app/; `npm run dev` serves from the root
  base: command === 'build' ? '/public/app/' : '/',
  build: {
    outDir: '../backend/public/app',
    emptyOutDir: true,
    sourcemap: false,
    target: 'es2019'
  },
  server: {
    port: 5173,
    // `npm run dev` talks to a backend on :8099 (PORT=8099 node server.js)
    // API_TARGET points the dev server at another backend (default :8099)
    proxy: { '/api': process.env.API_TARGET || 'http://localhost:8099', '^/s/': process.env.API_TARGET || 'http://localhost:8099' }
  },
  test: { environment: 'node', include: ['src/**/*.test.ts'] }
}));
