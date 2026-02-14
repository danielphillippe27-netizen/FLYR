import { useState } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { useLeads } from '../hooks/useLeads'
import LeadRow from './LeadRow'
import SyncSettingsView from './SyncSettingsView'

export default function LeadsPage() {
  const { user } = useAuth()
  const [showSyncSettings, setShowSyncSettings] = useState(false)
  const {
    leads,
    searchText,
    setSearchText,
    loading,
    error,
    load,
    hasConnectedCRM,
  } = useLeads(user?.id)

  const syncStatusText = hasConnectedCRM ? 'Synced' : 'Sync'
  const syncStatusColor = hasConnectedCRM ? '#34C759' : 'var(--accent)'

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg)' }}>
      <header style={{ padding: '8px 16px 12px', borderBottom: '1px solid #222' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 8 }}>
          <h1 style={{ fontSize: 28, fontWeight: 700, margin: 0 }}>Leads</h1>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ fontSize: 17, color: syncStatusColor }}>{syncStatusText}</span>
            <span style={{ color: syncStatusColor, fontSize: 17 }}>
              {hasConnectedCRM ? '✓' : '○'}
            </span>
            <button
              type="button"
              onClick={() => setShowSyncSettings(true)}
              style={{
                marginLeft: 8,
                padding: '4px 10px',
                fontSize: 14,
                background: 'var(--bg-secondary)',
                border: '1px solid #333',
                borderRadius: 8,
                color: 'var(--text)',
                cursor: 'pointer',
              }}
            >
              Sync Settings
            </button>
          </div>
        </div>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            padding: '8px 12px',
            background: 'rgba(255,255,255,0.08)',
            borderRadius: 10,
          }}
        >
          <span style={{ color: 'var(--muted)', fontSize: 16 }} aria-hidden>🔍</span>
          <input
            type="search"
            placeholder="Search field leads..."
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            style={{
              flex: 1,
              border: 'none',
              background: 'transparent',
              color: 'var(--text)',
              fontSize: 15,
              outline: 'none',
            }}
          />
        </div>
      </header>

      {error && (
        <div style={{ padding: 16, color: 'var(--accent)' }}>
          {error}
          <button type="button" onClick={() => load()} style={{ marginLeft: 12, textDecoration: 'underline' }}>
            Retry
          </button>
        </div>
      )}

      {loading && (
        <div style={{ padding: 48, textAlign: 'center', color: 'var(--muted)' }}>
          Loading...
        </div>
      )}

      {!loading && !error && leads.length === 0 && (
        <div style={{ padding: 48, textAlign: 'center' }}>
          <div style={{ fontSize: 48, marginBottom: 20 }}>📍</div>
          <h2 style={{ fontSize: 20, fontWeight: 600, marginBottom: 8 }}>No field leads yet</h2>
          <p style={{ color: 'var(--muted)', marginBottom: 24, maxWidth: 280, margin: '0 auto 24px' }}>
            Start a session in the app to capture leads, or add a lead manually from the web.
          </p>
          <button
            type="button"
            onClick={() => setShowSyncSettings(true)}
            style={{
              padding: '12px 20px',
              fontSize: 16,
              fontWeight: 500,
              background: 'var(--accent)',
              color: 'white',
              border: 'none',
              borderRadius: 12,
              cursor: 'pointer',
            }}
          >
            Sync Settings
          </button>
        </div>
      )}

      {!loading && !error && leads.length > 0 && (
        <div style={{ paddingBottom: 24 }}>
          <button
            type="button"
            onClick={() => load()}
            style={{
              margin: '12px 16px',
              padding: '8px 14px',
              fontSize: 14,
              background: 'var(--bg-secondary)',
              border: '1px solid #333',
              borderRadius: 8,
              color: 'var(--text)',
              cursor: 'pointer',
            }}
          >
            Refresh
          </button>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            {leads.map((lead) => (
              <li key={lead.id}>
                <LeadRow lead={lead} />
                <div style={{ height: 1, background: '#222', marginLeft: 56 }} />
              </li>
            ))}
          </ul>
        </div>
      )}

      {showSyncSettings && (
        <SyncSettingsView
          onClose={() => setShowSyncSettings(false)}
          onSaved={() => {
            setShowSyncSettings(false)
            load()
          }}
        />
      )}
    </div>
  )
}
