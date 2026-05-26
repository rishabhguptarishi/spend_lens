import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    react(),
  ],
  server: {
    // Allow Vite inside Docker; browser on host uses localhost:3036 for HMR
    host: true,
    port: 3036,
    hmr: {
      host: 'localhost',
      port: 3036,
    },
  },
})
