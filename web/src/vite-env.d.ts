/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_MAPBOX_ACCESS_TOKEN?: string
  readonly VITE_MAPBOX_TOKEN?: string
  readonly VITE_MAPBOX_STYLE_LIGHT?: string
}

declare const __FLYR_MAPBOX_ACCESS_TOKEN__: string | undefined

declare module '*.css' {
  const src: string
  export default src
}
