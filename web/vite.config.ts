import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: 'http://localhost:8765',
        rewrite: (p) => p.replace(/^\/api/, ''),
      },
      '/ws': {
        target: 'ws://localhost:8765',
        ws: true,
      },
    },
  },
});
