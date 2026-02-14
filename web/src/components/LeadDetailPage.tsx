import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { supabase } from '../supabase'
import { fetchCRMConnections } from '../lib/integrations'
import { fetchUserIntegrations } from '../lib/integrations'
import { FIELD_LEAD_STATUS_LABELS } from '../lib/leadDisplay'
import { downloadCsv } from '../lib/exportLeads'
import type { FieldLead } from '../types/leads'
import type { CRMConnection, UserIntegration } from '../types/leads'
import SyncSettingsView from './SyncSettingsView'

const PROVIDER_NAMES: Record<string, string> = {
  fub: 'Follow Up Boss',
  kvcore: 'KVCore',
  zapier: 'Zapier',
  hubspot: 'HubSpot',
  monday: 'Monday.com',
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString()
}

function formatRelative(iso: string) {
  const d = new Date(iso)
  const now = new Date()
  const sec = Math.floor((now.getTime() - d.getTime()) / 1000)
  if (sec < 60) return 'just now'
  if (sec < 3600) return `${Math.floor(sec / 60)}m ago`
  if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`
  return d.toLocaleDateString()
}

export default function LeadDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [lead, setLead] = useState<FieldLead | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [connections, setConnections] = useState<CRMConnection[]>([])
  const [integrations, setIntegrations] = useState<UserIntegration[]>([])
  const [showSyncSettings, setShowSyncSettings] = useState(false)

  useEffect(() => {
    if (!id || !supabase) return
    supabase
      .from('field_leads')
      .select('*')
      .eq('id', id)
      .maybeSingle()
      .then(({ data, error: err }) => {
        if (err) setError(err.message)
        else setLead(data as FieldLead | null)
        setLoading(false)
      })
  }, [id])

  useEffect(() => {
    if (!user?.id) return
    Promise.all([fetchCRMConnections(user.id), fetchUserIntegrations(user.id)]).then(
      ([c, i]) => {
        setConnections(c)
        setIntegrations(i)
      }
    )
  }, [user?.id])

  const connectedProvider =
    connections.find((c) => c.status === 'connected')?.provider
      ? PROVIDER_NAMES[connections.find((c) => c.status === 'connected')!.provider]
      : integrations.find((i) => i.api_key || i.webhook_url)
        ? PROVIDER_NAMES[integrations.find((i) => i.api_key || i.webhook_url)!.provider]
        : null

  const lastSynced = lead?.last_synced_at ? formatRelative(lead.last_synced_at) : null

  function handleShare() {
    if (!lead) return
    const lines = [
      `Address: ${lead.address}`,
      `Name: ${lead.name?.trim() || 'Unknown'}`,
      `Status: ${FIELD_LEAD_STATUS_LABELS[lead.status]}`,
      `Created: ${formatDate(lead.created_at)}`,
    ]
    if (lead.phone) lines.splice(2, 0, `Phone: ${lead.phone}`)
    if (lead.notes) lines.push(`Notes: ${lead.notes}`)
    if (lead.qr_code) lines.push(`QR: ${lead.qr_code}`)
    navigator.clipboard.writeText(lines.join('\n'))
  }

  function handleExport() {
    if (!lead) return
    downloadCsv([lead], `lead_${lead.id.slice(0, 8)}.csv`)
  }

  function openInMaps() {
    if (!lead) return
    const url = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(lead.address)}`
    window.open(url, '_blank')
  }

  if (loading) return <div style={{ padding: 24 }}>Loading...</div>
  if (error || !lead) return <div style={{ padding: 24, color: 'var(--accent)' }}>{error ?? 'Lead not found'}</div>

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg)', padding: 20 }}>
      <button type="button" onClick={() => navigate('/leads')} style={{ marginBottom: 16, background: 'none', border: 'none', color: 'var(--muted)', cursor: 'pointer', fontSize: 14 }}>← Back to Leads</button>

      <h1 style={{ fontSize: 22, marginBottom: 24 }}>{lead.address}</h1>

      <section style={{ marginBottom: 24 }}>
        <h2 style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)', marginBottom: 8 }}>Address</h2>
        <p style={{ marginBottom: 8 }}>{lead.address}</p>
        <button type="button" onClick={openInMaps} style={{ color: 'var(--accent)', background: 'none', border: 'none', cursor: 'pointer', fontSize: 15 }}>Open in Maps</button>
      </section>

      <section style={{ marginBottom: 24 }}>
        <h2 style={{ fontSize: 16, fontWeight: 600, marginBottom: 12 }}>Field Notes</h2>
        <div style={{ borderTop: '1px solid #333', paddingTop: 12 }}>
          <p><span style={{ color: 'var(--muted)' }}>Status:</span> {FIELD_LEAD_STATUS_LABELS[lead.status]}</p>
          <p style={{ fontSize: 14, color: 'var(--muted)' }}>Last: {formatDate(lead.created_at)}</p>
          {lead.session_id && <p style={{ fontSize: 13, color: 'var(--muted)' }}>Captured during Session</p>}
          {lead.notes && <p style={{ marginTop: 8 }}>{lead.notes}</p>}
        </div>
      </section>

      {lead.qr_code && (
        <section style={{ marginBottom: 24 }}>
          <h2 style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)', marginBottom: 8 }}>QR Scan</h2>
          <p>{lead.qr_code}</p>
        </section>
      )}

      <section style={{ marginBottom: 24 }}>
        {connectedProvider ? (
          <div style={{ padding: 16, background: 'rgba(255,255,255,0.06)', borderRadius: 12 }}>
            <p style={{ display: 'flex', alignItems: 'center', gap: 8 }}><span style={{ color: '#34C759' }}>✓</span> Synced to {connectedProvider}</p>
            {lastSynced && <p style={{ fontSize: 13, color: 'var(--muted)' }}>Last sync: {lastSynced}</p>}
          </div>
        ) : (
          <div style={{ padding: 16, background: 'rgba(0,122,255,0.15)', borderRadius: 12 }}>
            <p style={{ fontWeight: 600, marginBottom: 4 }}>Pro Tip</p>
            <p style={{ fontSize: 14, color: 'var(--muted)', marginBottom: 12 }}>Connect FUB to auto-sync this lead to your office.</p>
            <button type="button" onClick={() => setShowSyncSettings(true)} style={{ color: 'var(--accent)', background: 'none', border: 'none', cursor: 'pointer', fontSize: 14 }}>Connect CRM →</button>
          </div>
        )}
      </section>

      <section style={{ display: 'flex', gap: 12 }}>
        <button type="button" onClick={handleShare} style={{ flex: 1, padding: 12, background: 'rgba(255,255,255,0.1)', border: '1px solid #333', borderRadius: 10, color: 'var(--text)', cursor: 'pointer', fontSize: 15 }}>Share Lead</button>
        <button type="button" onClick={handleExport} style={{ flex: 1, padding: 12, background: 'rgba(255,255,255,0.1)', border: '1px solid #333', borderRadius: 10, color: 'var(--text)', cursor: 'pointer', fontSize: 15 }}>Export</button>
      </section>

      {showSyncSettings && <SyncSettingsView onClose={() => setShowSyncSettings(false)} onSaved={() => setShowSyncSettings(false)} />}
    </div>
  )
}
