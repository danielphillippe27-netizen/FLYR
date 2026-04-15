import { useEffect, useRef } from 'react'
import L, { type LatLngExpression, type Map as LeafletMap } from 'leaflet'

type Props = {
  path: [number, number][]
  latestPoint: [number, number]
}

const markerIcon = L.divIcon({
  className: 'beacon-marker',
  html: '<div class="beacon-marker__dot"></div>',
  iconSize: [18, 18],
  iconAnchor: [9, 9],
})

export default function BeaconMap({ path, latestPoint }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<LeafletMap | null>(null)
  const pathRef = useRef<L.Polyline | null>(null)
  const markerRef = useRef<L.Marker | null>(null)

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return

    const map = L.map(containerRef.current, {
      zoomControl: false,
    })

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(map)

    mapRef.current = map

    return () => {
      map.remove()
      mapRef.current = null
    }
  }, [])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    const latLngs = path as LatLngExpression[]

    if (!pathRef.current) {
      pathRef.current = L.polyline(latLngs, {
        color: '#ff4f4f',
        weight: 5,
      }).addTo(map)
    } else {
      pathRef.current.setLatLngs(latLngs)
    }

    if (!markerRef.current) {
      markerRef.current = L.marker(latestPoint, { icon: markerIcon }).addTo(map)
    } else {
      markerRef.current.setLatLng(latestPoint)
    }

    if (latLngs.length > 1) {
      map.fitBounds(pathRef.current.getBounds(), {
        padding: [40, 40],
        maxZoom: 17,
      })
    } else {
      map.setView(latestPoint, 16)
    }
  }, [path, latestPoint])

  return <div ref={containerRef} className="beacon-map" />
}
