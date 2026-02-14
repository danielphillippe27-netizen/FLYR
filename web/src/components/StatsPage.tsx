import { useUserStats } from '../hooks/useUserStats'
import { formatDistanceWalked } from '../types/userStats'
import StatCard from './StatCard'
import SuccessMetricBar from './SuccessMetricBar'

function formatUpdatedAt(updatedAt: string): string {
  if (!updatedAt) return 'Updated just now'
  try {
    const d = new Date(updatedAt)
    const now = new Date()
    const diffMs = now.getTime() - d.getTime()
    const diffMins = Math.floor(diffMs / 60000)
    if (diffMins < 1) return 'Updated just now'
    if (diffMins < 60) return `Updated ${diffMins}m ago`
    const diffHours = Math.floor(diffMins / 60)
    if (diffHours < 24) return `Updated ${diffHours}h ago`
    return d.toLocaleDateString()
  } catch {
    return 'Updated just now'
  }
}

/** Normalize rate to 0–100 for display (DB may store 0–1 or 0–100). */
function ratePercent(value: number): number {
  if (value <= 1) return value * 100
  return value
}

export default function StatsPage() {
  const { stats, userId, selectedTab, setSelectedTab, isLoading, error, retry } = useUserStats()

  if (isLoading) {
    return (
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: 24,
        }}
      >
        <div style={{ fontSize: 18, color: 'var(--muted)' }}>Loading…</div>
      </div>
    )
  }

  if (error) {
    return (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: 24,
          gap: 16,
        }}
      >
        <span style={{ fontSize: 48, opacity: 0.5 }}>⚠️</span>
        <p
          style={{
            fontSize: 15,
            color: 'var(--muted)',
            textAlign: 'center',
            maxWidth: 320,
          }}
        >
          {error}
        </p>
        <button
          type="button"
          onClick={retry}
          style={{
            padding: '10px 20px',
            fontSize: 15,
            fontWeight: 600,
            color: 'white',
            background: 'var(--accent)',
            border: 'none',
            borderRadius: 8,
            cursor: 'pointer',
          }}
        >
          Retry
        </button>
      </div>
    )
  }

  if (!userId || !stats) {
    return (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: 24,
          gap: 16,
        }}
      >
        <p style={{ fontSize: 15, color: 'var(--muted)' }}>
          Please sign in to view your stats
        </p>
      </div>
    )
  }

  return (
    <div style={{ background: 'var(--bg)', minHeight: '100vh' }}>
      <header
        style={{
          padding: '16px 20px 8px',
          borderBottom: '1px solid rgba(255,255,255,0.08)',
        }}
      >
        <h1
          style={{
            margin: 0,
            fontSize: 22,
            fontWeight: 700,
            color: 'var(--text)',
          }}
        >
          Your Stats
        </h1>
      </header>

      <div style={{ padding: '8px 20px 24px' }}>
        {/* Header row */}
        <div style={{ marginBottom: 24 }}>
          <h2 style={{ margin: 0, fontSize: 28, fontWeight: 700, color: 'var(--text)' }}>
            Your Stats
          </h2>
          <p style={{ margin: '4px 0 0', fontSize: 14, color: 'var(--muted)' }}>
            {formatUpdatedAt(stats.updated_at)}
          </p>
        </div>

        {/* Streaks */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 16,
            marginBottom: 24,
          }}
        >
          <StatCard
            icon="🔥"
            color="var(--accent)"
            title="Day Streak"
            value={stats.day_streak}
          />
          <StatCard
            icon="🏆"
            color="var(--gold)"
            title="Best Streak"
            value={stats.best_streak}
          />
        </div>

        {/* Time period */}
        <div
          style={{
            display: 'flex',
            gap: 8,
            marginBottom: 24,
          }}
        >
          {(['Week', 'All Time'] as const).map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setSelectedTab(tab)}
              style={{
                flex: 1,
                height: 36,
                fontSize: 15,
                fontWeight: 600,
                color: selectedTab === tab ? 'white' : 'var(--text)',
                background: selectedTab === tab ? 'var(--accent)' : 'rgba(255,255,255,0.1)',
                border: 'none',
                borderRadius: 18,
                cursor: 'pointer',
              }}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Stats grid */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 16,
            marginBottom: 24,
          }}
        >
          <StatCard
            icon="🚪"
            color="#3b82f6"
            title="Doors Knocked"
            value={stats.doors_knocked}
          />
          <StatCard
            icon="📄"
            color="#22c55e"
            title="Flyers"
            value={stats.flyers}
          />
          <StatCard
            icon="💬"
            color="#a855f7"
            title="Conversations"
            value={stats.conversations}
          />
          <StatCard
            icon="⭐"
            color="var(--accent)"
            title="Leads Created"
            value={stats.leads_created}
          />
          <StatCard
            icon="📱"
            color="#ef4444"
            title="QR Codes Scanned"
            value={stats.qr_codes_scanned}
          />
          <StatCard
            icon="🚶"
            color="#06b6d4"
            title="Distance Walked"
            value={formatDistanceWalked(stats.distance_walked)}
          />
          <StatCard
            icon="✨"
            color="var(--gold)"
            title="Experience Points"
            value={stats.xp}
          />
        </div>

        {/* Success metrics */}
        <section style={{ marginTop: 8 }}>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              marginBottom: 16,
            }}
          >
            <span style={{ fontSize: 18, color: '#22c55e' }}>📈</span>
            <h3
              style={{
                margin: 0,
                fontSize: 20,
                fontWeight: 600,
                color: 'var(--text)',
              }}
            >
              Success Metrics
            </h3>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <SuccessMetricBar
              title="Conversations per Door"
              value={ratePercent(stats.conversation_per_door)}
              icon="💬"
              color="#a855f7"
              description="Conversations per door knocked"
            />
            <SuccessMetricBar
              title="Conversation–Lead Rate"
              value={ratePercent(stats.conversation_lead_rate)}
              icon="⭐"
              color="var(--gold)"
              description="Leads per conversation"
            />
            <SuccessMetricBar
              title="FLYR™ QR Code Scan"
              value={ratePercent(stats.qr_code_scan_rate)}
              icon="📱"
              color="#ef4444"
              description="QR code scans per flyer"
            />
          </div>
        </section>

        {/* Refresh */}
        <div style={{ marginTop: 32, textAlign: 'center' }}>
          <button
            type="button"
            onClick={retry}
            style={{
              padding: '10px 20px',
              fontSize: 14,
              fontWeight: 500,
              color: 'var(--text)',
              background: 'rgba(255,255,255,0.08)',
              border: '1px solid rgba(255,255,255,0.12)',
              borderRadius: 8,
              cursor: 'pointer',
            }}
          >
            Refresh
          </button>
        </div>
      </div>
    </div>
  )
}
