import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The built app is committed into backend/public/app and served by the
// backend (routes/webAppRoutes.js): Cloud Run's image is built from backend/
// alone, by whichever session runs deploy.sh. Assets load from /public/app/.
export default defineConfig({
  plugins: [react()],
  base: '/public/app/',
  build: {
    outDir: '../backend/public/app',
    emptyOutDir: true,
    sourcemap: false,
    target: 'es2019'
  },
  server: {
    port: 5173,
    // `npm run dev` talks to a backend on :8099 (PORT=8099 node server.js)
    proxy: { '/api': 'http://localhost:8099', '/public': 'http://localhost:8099' }
  },
  test: { environment: 'node', include: ['src/**/*.test.ts'] }
});
