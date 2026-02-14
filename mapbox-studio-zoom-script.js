/**
 * MAPBOX STUDIO ZOOM LEVEL SCRIPT
 * 
 * Run this in Chrome DevTools console while on studio.mapbox.com
 * with a style open in the editor.
 * 
 * This script extracts and/or modifies layer zoom levels to match
 * the Mapbox Standard v11 reference.
 */

// ============================================
// STEP 1: Find the map instance
// ============================================

function findMapInstance() {
  // Mapbox Studio typically exposes the map on window or via React internals
  if (window.map) return window.map;
  if (window.__MAPBOX_STUDIO__?.map) return window.__MAPBOX_STUDIO__.map;
  
  // Try to find it in the DOM
  const mapContainer = document.querySelector('.mapboxgl-map');
  if (mapContainer?._mapboxGL) return mapContainer._mapboxGL;
  
  // Search for mapbox-gl instances
  const canvases = document.querySelectorAll('canvas');
  for (const canvas of canvases) {
    const parent = canvas.closest('.mapboxgl-map');
    if (parent && parent.__mbglMap) return parent.__mbglMap;
  }
  
  // Last resort: search window for map-like objects
  for (const key of Object.keys(window)) {
    const val = window[key];
    if (val && typeof val.getStyle === 'function' && typeof val.getLayer === 'function') {
      console.log(`Found map at window.${key}`);
      return val;
    }
  }
  
  return null;
}

// ============================================
// STEP 2: Get current style
// ============================================

function getStyleJSON() {
  const map = findMapInstance();
  if (map) {
    const style = map.getStyle();
    console.log('Got style from map instance');
    return style;
  }
  
  // Try to get it from Studio's internal state
  // Look for React fiber or Redux store
  const root = document.getElementById('root') || document.getElementById('app');
  if (root?._reactRootContainer) {
    console.log('Found React root, searching for style state...');
    // This would require traversing React internals
  }
  
  return null;
}

// ============================================
// STEP 3: V11 Standard Zoom Reference
// ============================================

const V11_ZOOM_LEVELS = {
  // ROADS
  'road-motorway': { minzoom: 5, maxzoom: 14 },
  'road-motorway-trunk': { minzoom: 5, maxzoom: 14 },
  'road-trunk': { minzoom: 5, maxzoom: 14 },
  'road-primary': { minzoom: 7, maxzoom: 14 },
  'road-secondary': { minzoom: 8, maxzoom: 14 },
  'road-street': { minzoom: 11, maxzoom: 14 },
  'road-street-minor': { minzoom: 13, maxzoom: 14 },
  'road-service': { minzoom: 14, maxzoom: 14 },
  'road-path': { minzoom: 14, maxzoom: 14 },
  'road-pedestrian': { minzoom: 14, maxzoom: 14 },
  
  // ROAD LABELS
  'road-label': { minzoom: 10 },
  'road-number-shield': { minzoom: 6 },
  
  // BUILDINGS
  'building': { minzoom: 13 },
  'building-extrusion': { minzoom: 15 },
  'building-2d': { minzoom: 13, maxzoom: 15 },
  
  // POI
  'poi-label': { minzoom: 6 },
  
  // PLACE LABELS
  'settlement-major-label': { minzoom: 3 },
  'settlement-minor-label': { minzoom: 5 },
  'settlement-subdivision-label': { minzoom: 10 },
  'country-label': { minzoom: 1 },
  'state-label': { minzoom: 3 },
  
  // WATER
  'water': { minzoom: 0 },
  'water-line': { minzoom: 8 },
  'waterway': { minzoom: 8 },
  'waterway-label': { minzoom: 12 },
  
  // LAND USE
  'landuse': { minzoom: 5 },
  'national-park': { minzoom: 5 },
  'landcover': { minzoom: 0 },
  
  // ADMIN BOUNDARIES
  'admin-0-boundary': { minzoom: 1 },
  'admin-1-boundary': { minzoom: 2 },
  'admin-0-boundary-disputed': { minzoom: 1 },
  
  // TRANSIT
  'transit-label': { minzoom: 12 },
  'airport-label': { minzoom: 8 },
  'aeroway': { minzoom: 11 },
};

// ============================================
// STEP 4: Apply zoom levels
// ============================================

function applyZoomLevels(style) {
  if (!style || !style.layers) {
    console.error('No style or layers found');
    return null;
  }
  
  let modified = 0;
  
  for (const layer of style.layers) {
    const id = layer.id;
    
    // Check for exact match
    if (V11_ZOOM_LEVELS[id]) {
      const ref = V11_ZOOM_LEVELS[id];
      if (ref.minzoom !== undefined) layer.minzoom = ref.minzoom;
      if (ref.maxzoom !== undefined) layer.maxzoom = ref.maxzoom;
      modified++;
      console.log(`✓ ${id}: minzoom=${layer.minzoom}, maxzoom=${layer.maxzoom}`);
      continue;
    }
    
    // Check for partial match
    for (const [pattern, ref] of Object.entries(V11_ZOOM_LEVELS)) {
      if (id.includes(pattern) || id.startsWith(pattern.split('-')[0])) {
        if (ref.minzoom !== undefined) layer.minzoom = ref.minzoom;
        if (ref.maxzoom !== undefined) layer.maxzoom = ref.maxzoom;
        modified++;
        console.log(`~ ${id} (matched ${pattern}): minzoom=${layer.minzoom}, maxzoom=${layer.maxzoom}`);
        break;
      }
    }
  }
  
  console.log(`\nModified ${modified} layers`);
  return style;
}

// ============================================
// STEP 5: Export / Download style
// ============================================

function downloadStyle(style, filename = 'flyr-standard-v10.json') {
  const json = JSON.stringify(style, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  
  console.log(`Downloaded ${filename}`);
}

// ============================================
// MAIN EXECUTION
// ============================================

console.log('🗺️ Mapbox Studio Zoom Script');
console.log('============================\n');

// Try to get the style
const style = getStyleJSON();

if (style) {
  console.log(`Found style: "${style.name || 'Untitled'}"`);
  console.log(`Layers: ${style.layers?.length || 0}`);
  console.log(`Sources: ${Object.keys(style.sources || {}).length}`);
  console.log('\n--- Layer Summary ---');
  
  // Group layers by type
  const byType = {};
  for (const layer of style.layers || []) {
    const type = layer.type || 'unknown';
    byType[type] = (byType[type] || 0) + 1;
  }
  console.table(byType);
  
  console.log('\n--- Applying V11 Zoom Levels ---');
  const modified = applyZoomLevels(style);
  
  if (modified) {
    console.log('\n✅ Style modified. Run downloadStyle(style) to save it.');
    window._modifiedStyle = modified;
  }
} else {
  console.log('❌ Could not find map/style instance.');
  console.log('\nTry these commands manually:');
  console.log('  1. Check window.map');
  console.log('  2. Check document.querySelector(".mapboxgl-map").__mapbox');
  console.log('  3. Look for map in React DevTools');
}

// Export functions for manual use
window.findMapInstance = findMapInstance;
window.getStyleJSON = getStyleJSON;
window.applyZoomLevels = applyZoomLevels;
window.downloadStyle = downloadStyle;
window.V11_ZOOM_LEVELS = V11_ZOOM_LEVELS;

console.log('\n📋 Available functions:');
console.log('  findMapInstance() - Find the Mapbox GL map');
console.log('  getStyleJSON() - Get current style JSON');
console.log('  applyZoomLevels(style) - Apply v11 zoom levels');
console.log('  downloadStyle(style, filename) - Download as JSON');
console.log('  V11_ZOOM_LEVELS - Reference zoom values');
