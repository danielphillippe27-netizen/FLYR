import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

function parseXcconfigValue(contents: string, key: string) {
  const pattern = new RegExp(`^${key}\\s*=\\s*(.+)$`, 'm')
  const match = contents.match(pattern)
  if (!match) return ''

  const value = match[1].trim()
  if (
    !value
    || value === 'YOUR_MAPBOX_PUBLIC_TOKEN'
    || value === 'REPLACE_WITH_YOUR_MAPBOX_PUBLIC_TOKEN'
    || value.startsWith('$(')
  ) {
    return ''
  }

  return value
}

function loadSharedMapboxToken() {
  const configPath = resolve(process.cwd(), '../Config.local.xcconfig')
  if (!existsSync(configPath)) return ''

  const contents = readFileSync(configPath, 'utf8')
  return parseXcconfigValue(contents, 'MAPBOX_ACCESS_TOKEN')
}

export default defineConfig({
  plugins: [react()],
  define: {
    __FLYR_MAPBOX_ACCESS_TOKEN__: JSON.stringify(
      process.env.VITE_MAPBOX_ACCESS_TOKEN
        || process.env.VITE_MAPBOX_TOKEN
        || process.env.MAPBOX_ACCESS_TOKEN
        || loadSharedMapboxToken()
    ),
  },
})
