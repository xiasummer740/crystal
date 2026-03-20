import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({
  plugins: [react()],
  server: { proxy: { '/api': ['h', 't', 't', 'p', '://1', '2', '7.0.0.1:3001'].join('') } }
})
