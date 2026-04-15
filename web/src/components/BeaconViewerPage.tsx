import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import BeaconMap from './BeaconMap'
import { fetchPublicBeacon, type BeaconPayload } from '../lib/beacon'

const POLL_INTERVAL_MS = 15000

function formatElapsed(start?: string, end?: string | null) {
  if (!start) return '--'
  const startDate = new Date(start)
  const endDate = end ? new Date(end) : new Date()
  const totalSeconds = Math.max(0, Math.floor((endDate.getTime() - startDate.getTime()) / 1000))
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  if (hours > 0) {
    return `${hours}h ${minutes}m`
  }
  return `${minutes}m`
}

function formatTime(value?: string | null) {
  if (!value) return '--'
  return new Date(value).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
}

function formatDistance(meters?: number | null) {
  if (!meters || meters <= 0) return '--'
  return `${(meters / 1000).toFixed(2)} km`
}

function formatBattery(level?: number | null) {
  if (typeof level !== 'number' || Number.isNaN(level)) return '--'
  return `${Math.round(level * 100)}%`
}

export default function BeaconViewerPage() {
  const { token } = useParams<{ token: string }>()
  const [payload, setPayload] = useState<BeaconPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!token) return
    let cancelled = false

    const load = async () => {
      try {
        const next = await fetchPublicBeacon(token)
        if (!cancelled) {
          setPayload(next)
          setError(null)
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Could not load Beacon')
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    void load()
    const intervalId = window.setInterval(() => {
      void load()
    }, POLL_INTERVAL_MS)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [token])

  const path = useMemo(
    () => (payload?.breadcrumbs ?? []).map((point) => [point.lat, point.lon] as [number, number]),
    [payload]
  )

  const latestPoint = payload?.latest_heartbeat
    ? ([payload.latest_heartbeat.lat, payload.latest_heartbeat.lon] as [number, number])
    : path[path.length - 1]

  if (loading) {
    return (
      <main className="beacon-page beacon-page--centered">
        <p className="beacon-eyebrow">FLYR Beacon</p>
        <h1>Loading live session…</h1>
      </main>
    )
  }

  if (error) {
    return (
      <main className="beacon-page beacon-page--centered">
        <p className="beacon-eyebrow">FLYR Beacon</p>
        <h1>Couldn’t load this session</h1>
        <p className="beacon-muted">{error}</p>
      </main>
    )
  }

  if (!payload?.active || !payload.session || !latestPoint) {
    return (
      <main className="beacon-page beacon-page--centered">
        <p className="beacon-eyebrow">FLYR Beacon</p>
        <h1>This Beacon link is no longer active</h1>
        <p className="beacon-muted">Session sharing turns off automatically when the session ends or the link is revoked.</p>
      </main>
    )
  }

  const session = payload.session
  const latestHeartbeat = payload.latest_heartbeat
  const battery = latestHeartbeat?.battery_level
  const safetyEvents = payload.safety_events ?? []

  return (
    <main className="beacon-page">
      <section className="beacon-header">
        <div>
          <p className="beacon-eyebrow">FLYR Beacon</p>
          <h1>{payload.share?.viewer_label?.trim() ? `${payload.share.viewer_label} can see this live session` : 'Live door knocking session'}</h1>
        </div>
        <div className={`beacon-status ${session.is_paused ? 'beacon-status--paused' : ''}`}>
          {session.is_paused ? 'Paused' : 'Live'}
        </div>
      </section>

      {safetyEvents.length > 0 && (
        <section className="beacon-alerts">
          {safetyEvents.map((event) => (
            <article key={event.id} className="beacon-alert">
              <strong>{event.event_type === 'missed_check_in' ? 'Missed safety check-in' : 'Safety alert'}</strong>
              <span>{event.message || 'A safety event was recorded for this session.'}</span>
              <time>{formatTime(event.created_at)}</time>
            </article>
          ))}
        </section>
      )}

      <section className="beacon-map-shell">
        <BeaconMap path={path} latestPoint={latestPoint} />
      </section>

      <section className="beacon-stats">
        <article>
          <span>Started</span>
          <strong>{formatTime(session.start_time)}</strong>
        </article>
        <article>
          <span>Elapsed</span>
          <strong>{formatElapsed(session.start_time, session.end_time)}</strong>
        </article>
        <article>
          <span>Last movement</span>
          <strong>{formatTime(latestHeartbeat?.recorded_at)}</strong>
        </article>
        <article>
          <span>Distance</span>
          <strong>{formatDistance(session.distance_meters)}</strong>
        </article>
        <article>
          <span>Doors</span>
          <strong>{session.flyers_delivered ?? session.completed_count ?? 0}</strong>
        </article>
        <article>
          <span>Battery</span>
          <strong>{formatBattery(battery)}</strong>
        </article>
      </section>
    </main>
  )
}
