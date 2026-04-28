import { useEffect, useMemo, useRef } from 'react'
import mapboxgl from 'mapbox-gl'
import type {
  BeaconCampaignFeatureCollection,
  BeaconSessionDoor,
} from '../lib/beacon'

type Props = {
  path: [number, number][]
  markerPoint?: [number, number] | null
  doors: BeaconSessionDoor[]
  campaignFeatures: BeaconCampaignFeatureCollection | null
}

const MAPBOX_ACCESS_TOKEN = (
  import.meta.env.VITE_MAPBOX_ACCESS_TOKEN
  ?? import.meta.env.VITE_MAPBOX_TOKEN
  ?? __FLYR_MAPBOX_ACCESS_TOKEN__
  ?? ''
).trim()

const MAPBOX_LIGHT_STYLE = (
  import.meta.env.VITE_MAPBOX_STYLE_LIGHT
  ?? 'mapbox://styles/mapbox/light-v11'
).trim()

const CAMPAIGN_SOURCE_ID = 'beacon-campaign-features'
const CAMPAIGN_BUILDINGS_LAYER_ID = 'beacon-campaign-buildings'
const CAMPAIGN_ADDRESSES_LAYER_ID = 'beacon-campaign-addresses'
const PATH_SOURCE_ID = 'beacon-session-path'
const PATH_LAYER_ID = 'beacon-session-path-line'
const DOORS_SOURCE_ID = 'beacon-session-doors'
const DOORS_LAYER_ID = 'beacon-session-doors-circle'
const PUCK_SOURCE_ID = 'beacon-session-puck'
const PUCK_HALO_LAYER_ID = 'beacon-session-puck-halo'
const PUCK_CORE_LAYER_ID = 'beacon-session-puck-core'
const DEFAULT_CENTER: [number, number] = [43.6532, -79.3832]

type MapSnapshot = {
  campaignCoordinates: [number, number][]
  campaignData: GeoJSON.GeoJSON
  doors: BeaconSessionDoor[]
  doorsData: GeoJSON.GeoJSON
  markerPoint: [number, number] | null
  path: [number, number][]
  pathData: GeoJSON.GeoJSON
  puckData: GeoJSON.GeoJSON
}

function emptyFeatureCollection() {
  return {
    type: 'FeatureCollection' as const,
    features: [],
  }
}

function isValidPoint(lat?: number | null, lon?: number | null) {
  if (typeof lat !== 'number' || typeof lon !== 'number') return false
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return false
  if (Math.abs(lat) > 90 || Math.abs(lon) > 180) return false
  if (Math.abs(lat) < 0.000001 && Math.abs(lon) < 0.000001) return false
  return true
}

function buildPathFeatureCollection(path: [number, number][]) {
  if (path.length === 0) return emptyFeatureCollection()

  return {
    type: 'FeatureCollection' as const,
    features: [
      {
        type: 'Feature' as const,
        geometry: {
          type: 'LineString' as const,
          coordinates: path.map(([lat, lon]) => [lon, lat]),
        },
        properties: {},
      },
    ],
  }
}

function buildDoorFeatureCollection(doors: BeaconSessionDoor[]) {
  return {
    type: 'FeatureCollection' as const,
    features: doors
      .filter((door) => isValidPoint(door.lat, door.lon))
      .map((door) => ({
        type: 'Feature' as const,
        geometry: {
          type: 'Point' as const,
          coordinates: [door.lon, door.lat],
        },
        properties: {
          address_id: door.address_id,
          formatted: door.formatted ?? null,
          house_number: door.house_number ?? null,
          street_name: door.street_name ?? null,
          status: door.status ?? 'none',
          map_status: door.map_status ?? 'not_visited',
          created_at: door.created_at,
        },
      })),
  }
}

function buildPuckFeatureCollection(markerPoint?: [number, number] | null) {
  if (!markerPoint) return emptyFeatureCollection()

  return {
    type: 'FeatureCollection' as const,
    features: [
      {
        type: 'Feature' as const,
        geometry: {
          type: 'Point' as const,
          coordinates: [markerPoint[1], markerPoint[0]],
        },
        properties: {},
      },
    ],
  }
}

function appendGeometryCoordinates(
  geometry: BeaconCampaignFeatureCollection['features'][number]['geometry'] | null | undefined,
  points: [number, number][]
) {
  if (!geometry) return

  const visit = (value: unknown) => {
    if (!Array.isArray(value) || value.length === 0) return

    if (typeof value[0] === 'number' && typeof value[1] === 'number') {
      const [lon, lat] = value as [number, number]
      if (Number.isFinite(lat) && Number.isFinite(lon)) {
        points.push([lat, lon])
      }
      return
    }

    for (const item of value) {
      visit(item)
    }
  }

  visit(geometry.coordinates)
}

function collectCampaignCoordinates(campaignFeatures: BeaconCampaignFeatureCollection | null) {
  const points: [number, number][] = []

  for (const feature of campaignFeatures?.features ?? []) {
    appendGeometryCoordinates(feature.geometry, points)
  }

  return points
}

function centerForPoints(points: [number, number][]) {
  if (points.length === 0) return null

  let minLat = points[0][0]
  let maxLat = points[0][0]
  let minLon = points[0][1]
  let maxLon = points[0][1]

  for (const [lat, lon] of points) {
    minLat = Math.min(minLat, lat)
    maxLat = Math.max(maxLat, lat)
    minLon = Math.min(minLon, lon)
    maxLon = Math.max(maxLon, lon)
  }

  return [(minLat + maxLat) / 2, (minLon + maxLon) / 2] as [number, number]
}

function extendBounds(bounds: mapboxgl.LngLatBounds, points: [number, number][]) {
  for (const [lat, lon] of points) {
    bounds.extend([lon, lat])
  }
}

function updateSourceData(map: mapboxgl.Map, sourceId: string, data: GeoJSON.GeoJSON) {
  const source = map.getSource(sourceId)
  if (source && source.type === 'geojson') {
    source.setData(data)
  }
}

function syncMapData(map: mapboxgl.Map, snapshot: MapSnapshot) {
  if (!map.isStyleLoaded()) return

  ensureLayers(map)
  updateSourceData(map, CAMPAIGN_SOURCE_ID, snapshot.campaignData)
  updateSourceData(map, PATH_SOURCE_ID, snapshot.pathData)
  updateSourceData(map, DOORS_SOURCE_ID, snapshot.doorsData)
  updateSourceData(map, PUCK_SOURCE_ID, snapshot.puckData)
}

function syncMapViewport(map: mapboxgl.Map, snapshot: MapSnapshot) {
  if (!map.isStyleLoaded()) return

  const bounds = new mapboxgl.LngLatBounds()
  let hasBounds = false
  const shouldUseCampaignBounds =
    snapshot.path.length === 0
    && snapshot.doors.length === 0
    && !snapshot.markerPoint
    && snapshot.campaignCoordinates.length > 0

  for (const [lat, lon] of snapshot.path) {
    bounds.extend([lon, lat])
    hasBounds = true
  }

  for (const door of snapshot.doors) {
    if (!isValidPoint(door.lat, door.lon)) continue
    bounds.extend([door.lon, door.lat])
    hasBounds = true
  }

  if (snapshot.markerPoint) {
    bounds.extend([snapshot.markerPoint[1], snapshot.markerPoint[0]])
    hasBounds = true
  }

  if (shouldUseCampaignBounds) {
    extendBounds(bounds, snapshot.campaignCoordinates)
    hasBounds = true
  }

  if (!hasBounds || bounds.isEmpty()) return

  if (snapshot.path.length + snapshot.doors.length > 1 || shouldUseCampaignBounds) {
    map.fitBounds(bounds, {
      padding: 56,
      maxZoom: 17.2,
      duration: 600,
      pitch: 58,
      bearing: -18,
    })
    return
  }

  if (snapshot.markerPoint) {
    map.easeTo({
      center: [snapshot.markerPoint[1], snapshot.markerPoint[0]],
      zoom: 16.3,
      pitch: 58,
      bearing: -18,
      duration: 600,
    })
  }
}

function ensureGeoJSONSource(map: mapboxgl.Map, sourceId: string) {
  if (!map.getSource(sourceId)) {
    map.addSource(sourceId, {
      type: 'geojson',
      data: emptyFeatureCollection(),
    })
  }
}

function ensureLayers(map: mapboxgl.Map) {
  ensureGeoJSONSource(map, CAMPAIGN_SOURCE_ID)
  ensureGeoJSONSource(map, PATH_SOURCE_ID)
  ensureGeoJSONSource(map, DOORS_SOURCE_ID)
  ensureGeoJSONSource(map, PUCK_SOURCE_ID)

  if (!map.getLayer(CAMPAIGN_BUILDINGS_LAYER_ID)) {
    map.addLayer({
      id: CAMPAIGN_BUILDINGS_LAYER_ID,
      type: 'fill-extrusion',
      source: CAMPAIGN_SOURCE_ID,
      filter: ['match', ['geometry-type'], ['Polygon', 'MultiPolygon'], true, false],
      paint: {
        'fill-extrusion-color': [
          'case',
          ['>', ['coalesce', ['get', 'scans_total'], 0], 0], '#8b5cf6',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'hot'], '#3b82f6',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'do_not_knock'], '#9ca3af',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'pending_visited'], '#f59e0b',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'visited'], '#22c55e',
          '#ef4444',
        ],
        'fill-extrusion-height': [
          'coalesce',
          ['get', 'height'],
          ['get', 'height_m'],
          10,
        ],
        'fill-extrusion-base': ['coalesce', ['get', 'min_height'], 0],
        'fill-extrusion-opacity': 1,
        'fill-extrusion-vertical-gradient': true,
      },
      minzoom: 12,
    })
  }

  if (!map.getLayer(CAMPAIGN_ADDRESSES_LAYER_ID)) {
    map.addLayer({
      id: CAMPAIGN_ADDRESSES_LAYER_ID,
      type: 'circle',
      source: CAMPAIGN_SOURCE_ID,
      filter: ['==', ['geometry-type'], 'Point'],
      paint: {
        'circle-radius': [
          'interpolate',
          ['linear'],
          ['zoom'],
          14, 4,
          18, 8,
        ],
        'circle-color': [
          'case',
          ['>', ['coalesce', ['get', 'scans_total'], 0], 0], '#8b5cf6',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'hot'], '#3b82f6',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'do_not_knock'], '#9ca3af',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'pending_visited'], '#f59e0b',
          ['==', ['coalesce', ['get', 'status'], 'not_visited'], 'visited'], '#22c55e',
          '#ef4444',
        ],
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff',
        'circle-opacity': 0.95,
      },
      minzoom: 14,
    })
  }

  if (!map.getLayer(PATH_LAYER_ID)) {
    map.addLayer({
      id: PATH_LAYER_ID,
      type: 'line',
      source: PATH_SOURCE_ID,
      layout: {
        'line-cap': 'round',
        'line-join': 'round',
      },
      paint: {
        'line-color': '#ff4f4f',
        'line-width': 5,
        'line-opacity': 0.95,
      },
    })
  }

  if (!map.getLayer(DOORS_LAYER_ID)) {
    map.addLayer({
      id: DOORS_LAYER_ID,
      type: 'circle',
      source: DOORS_SOURCE_ID,
      paint: {
        'circle-radius': 7,
        'circle-color': [
          'case',
          ['==', ['coalesce', ['get', 'map_status'], 'not_visited'], 'hot'], '#3b82f6',
          ['==', ['coalesce', ['get', 'map_status'], 'not_visited'], 'do_not_knock'], '#9ca3af',
          ['==', ['coalesce', ['get', 'map_status'], 'not_visited'], 'pending_visited'], '#f59e0b',
          ['==', ['coalesce', ['get', 'map_status'], 'not_visited'], 'no_answer'], '#f97316',
          ['==', ['coalesce', ['get', 'map_status'], 'not_visited'], 'visited'], '#22c55e',
          '#ef4444',
        ],
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff',
        'circle-opacity': 1,
      },
    })
  }

  if (!map.getLayer(PUCK_HALO_LAYER_ID)) {
    map.addLayer({
      id: PUCK_HALO_LAYER_ID,
      type: 'circle',
      source: PUCK_SOURCE_ID,
      paint: {
        'circle-radius': 13,
        'circle-color': 'rgba(255,79,79,0.22)',
      },
    })
  }

  if (!map.getLayer(PUCK_CORE_LAYER_ID)) {
    map.addLayer({
      id: PUCK_CORE_LAYER_ID,
      type: 'circle',
      source: PUCK_SOURCE_ID,
      paint: {
        'circle-radius': 7,
        'circle-color': '#ff4f4f',
        'circle-stroke-width': 3,
        'circle-stroke-color': '#ffffff',
      },
    })
  }
}

function addDoorPopup(map: mapboxgl.Map) {
  const popup = new mapboxgl.Popup({
    closeButton: false,
    closeOnClick: false,
    offset: 12,
  })

  const buildPopupContent = (title: string, status: string) => {
    const root = document.createElement('div')
    const heading = document.createElement('strong')
    const detail = document.createElement('div')

    heading.textContent = title
    detail.textContent = status

    root.append(heading, detail)
    return root
  }

  const onMouseEnter = () => {
    map.getCanvas().style.cursor = 'pointer'
  }

  const onMouseLeave = () => {
    map.getCanvas().style.cursor = ''
    popup.remove()
  }

  const onMouseMove = (event: mapboxgl.MapMouseEvent & { features?: mapboxgl.MapboxGeoJSONFeature[] }) => {
    const feature = event.features?.[0]
    if (!feature) return

    const coordinates = (feature.geometry as GeoJSON.Point).coordinates.slice() as [number, number]
    const properties = feature.properties ?? {}
    const houseNumber = String(properties.house_number ?? '').trim()
    const streetName = String(properties.street_name ?? '').trim()
    const formatted = String(properties.formatted ?? '').trim()
    const title = formatted || `${houseNumber} ${streetName}`.trim() || 'Door'
    const status = String(properties.status ?? 'completed')
      .replace(/_/g, ' ')
      .replace(/\b\w/g, (match: string) => match.toUpperCase())

    popup
      .setLngLat(coordinates)
      .setDOMContent(buildPopupContent(title, status))
      .addTo(map)
  }

  map.on('mouseenter', DOORS_LAYER_ID, onMouseEnter)
  map.on('mouseleave', DOORS_LAYER_ID, onMouseLeave)
  map.on('mousemove', DOORS_LAYER_ID, onMouseMove)

  return () => {
    popup.remove()
    map.off('mouseenter', DOORS_LAYER_ID, onMouseEnter)
    map.off('mouseleave', DOORS_LAYER_ID, onMouseLeave)
    map.off('mousemove', DOORS_LAYER_ID, onMouseMove)
  }
}

export default function BeaconMap({ path, markerPoint, doors, campaignFeatures }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<mapboxgl.Map | null>(null)
  const removeDoorPopupRef = useRef<() => void>(() => {})

  const campaignCoordinates = useMemo(
    () => collectCampaignCoordinates(campaignFeatures),
    [campaignFeatures]
  )
  const campaignCenter = useMemo(
    () => centerForPoints(campaignCoordinates),
    [campaignCoordinates]
  )
  const resolvedMarkerPoint = markerPoint
    ?? (doors[0] ? [doors[0].lat, doors[0].lon] as [number, number] : null)
    ?? campaignCenter
  const initialCenter = resolvedMarkerPoint ?? DEFAULT_CENTER
  const pathData = useMemo(() => buildPathFeatureCollection(path), [path])
  const doorsData = useMemo(() => buildDoorFeatureCollection(doors), [doors])
  const puckData = useMemo(() => buildPuckFeatureCollection(resolvedMarkerPoint), [resolvedMarkerPoint])
  const campaignData = useMemo(
    () => campaignFeatures ?? emptyFeatureCollection(),
    [campaignFeatures]
  )
  const snapshotRef = useRef<MapSnapshot>({
    campaignCoordinates,
    campaignData: campaignData as GeoJSON.GeoJSON,
    doors,
    doorsData: doorsData as GeoJSON.GeoJSON,
    markerPoint: resolvedMarkerPoint,
    path,
    pathData: pathData as GeoJSON.GeoJSON,
    puckData: puckData as GeoJSON.GeoJSON,
  })

  snapshotRef.current = {
    campaignCoordinates,
    campaignData: campaignData as GeoJSON.GeoJSON,
    doors,
    doorsData: doorsData as GeoJSON.GeoJSON,
    markerPoint: resolvedMarkerPoint,
    path,
    pathData: pathData as GeoJSON.GeoJSON,
    puckData: puckData as GeoJSON.GeoJSON,
  }

  useEffect(() => {
    if (!MAPBOX_ACCESS_TOKEN || !containerRef.current || mapRef.current) return

    mapboxgl.accessToken = MAPBOX_ACCESS_TOKEN

    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: MAPBOX_LIGHT_STYLE,
      center: [initialCenter[1], initialCenter[0]],
      zoom: 16,
      pitch: 58,
      bearing: -18,
      antialias: true,
    })

    map.dragRotate.enable()
    map.touchZoomRotate.enableRotation()
    mapRef.current = map

    const syncFromLatestSnapshot = () => {
      syncMapData(map, snapshotRef.current)
      syncMapViewport(map, snapshotRef.current)
      removeDoorPopupRef.current()
      removeDoorPopupRef.current = addDoorPopup(map)
      map.resize()
    }

    map.on('style.load', syncFromLatestSnapshot)

    return () => {
      removeDoorPopupRef.current()
      removeDoorPopupRef.current = () => {}
      map.off('style.load', syncFromLatestSnapshot)
      map.remove()
      mapRef.current = null
    }
  }, [])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    syncMapData(map, snapshotRef.current)
    syncMapViewport(map, snapshotRef.current)
  }, [campaignCoordinates, campaignData, doors, doorsData, path, pathData, puckData, resolvedMarkerPoint])

  if (!MAPBOX_ACCESS_TOKEN) {
    return (
      <div className="beacon-map beacon-map--fallback">
        Mapbox is not configured for the web app yet.
      </div>
    )
  }

  return <div ref={containerRef} className="beacon-map" />
}
