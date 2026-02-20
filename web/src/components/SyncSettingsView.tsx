import { useState, useEffect } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { fetchLeads } from '../lib/fieldLeads'
import { fetchCRMConnections, fetchUserIntegrations, connectKVCore, connectZapier } from '../lib/integrations'
import { downloadCsv } from '../lib/exportLeads'
import type { CRMConnection, UserIntegration } from '../types/leads'
import ConnectFUBModal from './ConnectFUBModal'

const PROVIDER_NAMES: Record<string, string> = {
  fub: 'Follow Up Boss',
  kvcore: 'KVCore',
  hubspot: 'HubSpot',
  monday: 'Monday.com',
  zapier: 'Zapier / Webhooks',
}

interface SyncSettingsViewProps {
  onClose: () => void
  onSaved?: () => void
}

export default function SyncSettingsView({ onClose, onSaved }: SyncSettingsViewProps) {
  const { user } = useAuth()
  const [connections, setConnections] = useState<CRMConnection[]>([])
  const [integrations, setIntegrations] = useState<UserIntegration[]>([])
  const [loading, setLoading] = useState(true)
  const [showFUB, setShowFUB] = useState(false)
  const [showKVCore, setShowKVCore] = useState(false)
  const [showZapier, setShowZapier] = useState(false)
  const [kvcoreKey, setKvcoreKey] = useState('')
  const [zapierUrl, setZapierUrl] = useState('')
  const [kvcoreError, setKvcoreError] = useState<string | null>(null)
  const [zapierError, setZapierError] = useState<string | null>(null)
  const [connectingKVCore, setConnectingKVCore] = useState(false)
  const [connectingZapier, setConnectingZapier] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [webhookUrl, setWebhookUrl] = useState(() => localStorage.getItem('flyr_leads_webhook_url') ?? '')
  const [testingWebhook, setTestingWebhook] = useState(false)
  const [webhookError, setWebhookError] = useState<string | null>(null)

  useEffect(() => {
    if (!webhookUrl) return
    localStorage.setItem('flyr_leads_webhook_url', webhookUrl)
  }, [webhookUrl])

  useEffect(() => {
    if (!user?.id) return
    Promise.all([fetchCRMConnections(user.id), fetchUserIntegrations(user.id)]).then(
      ([conns, ints]) => {
        setConnections(conns)
        setIntegrations(ints)
        setLoading(false)
      }
    ).catch(() => setLoading(false))
  }, [user?.id])

  const connectedName =
    connections.find((c) => c.status === 'connected')?.provider
      ? PROVIDER_NAMES[connections.find((c) => c.status === 'connected')!.provider] ?? connections.find((c) => c.status === 'connected')!.provider
      : integrations.some((i) => i.api_key || i.webhook_url)
        ? PROVIDER_NAMES[integrations.find((i) => i.api_key || i.webhook_url)?.provider ?? ''] ?? 'CRM'
        : 'None'

  async function handleConnectKVCore() {
    if (!user?.id || !kvcoreKey.trim()) return
    setKvcoreError(null)
    setConnectingKVCore(true)
    try {
      await connectKVCore(user.id, kvcoreKey)
      setShowKVCore(false)
      setKvcoreKey('')
      const ints = await fetchUserIntegrations(user.id)
      setIntegrations(ints)
      onSaved?.()
    } catch (e) {
      setKvcoreError(e instanceof Error ? e.message : 'Failed to connect')
    } finally {
      setConnectingKVCore(false)
    }
  }

  async function handleConnectZapier() {
    if (!user?.id || !zapierUrl.trim()) return
    setZapierError(null)
    setConnectingZapier(true)
    try {
      await connectZapier(user.id, zapierUrl)
      setShowZapier(false)
      setZapierUrl('')
      const ints = await fetchUserIntegrations(user.id)
      setIntegrations(ints)
      onSaved?.()
    } catch (e) {
      setZapierError(e instanceof Error ? e.message : 'Failed to connect')
    } finally {
      setConnectingZapier(false)
    }
  }

  async function handleExportCsv() {
    if (!user?.id) return
    setExporting(true)
    try {
      const leads = await fetchLeads(user.id)
      downloadCsv(leads, `contacts_${new Date().toISOString().slice(0, 10)}.csv`)
    } finally {
      setExporting(false)
    }
  }

  async function handleTestWebhook() {
    const url = webhookUrl.trim()
    if (!url) return
    setTestingWebhook(true)
    setWebhookError(null)
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          address: '123 Test St',
          name: 'Test Lead',
          status: 'interested',
          source: 'FLYR',
          created_at: new Date().toISOString(),
        }),
      })
      if (res.ok) setWebhookError(null)
      else setWebhookError(`Webhook returned ${res.status}`)
    } catch (e) {
      setWebhookError(e instanceof Error ? e.message : 'Request failed')
    } finally {
      setTestingWebhook(false)
    }
  }

  function handleFUBSuccess() {
    setShowFUB(false)
    if (!user?.id) return
    fetchCRMConnections(user.id).then(setConnections)
    onSaved?.()
  }

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.6)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
      }}
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        style={{
          background: 'var(--bg)',
          borderRadius: 16,
          maxWidth: 480,
          width: '90%',
          maxHeight: '90vh',
          overflow: 'auto',
          border: '1px solid #333',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
            <h2 style={{ margin: 0, fontSize: 20 }}>Sync Settings</h2>
            <button type="button" onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--muted)', cursor: 'pointer', fontSize: 18 }}>×</button>
          </div>

          {loading ? (
            <p style={{ color: 'var(--muted)' }}>Loading...</p>
          ) : (
            <>
              <section style={{ marginBottom: 24 }}>
                <h3 style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)', marginBottom: 8 }}>Connected</h3>
                <p style={{ fontSize: 18, margin: 0 }}>{connectedName}</p>
              </section>

              <section style={{ marginBottom: 24 }}>
                <h3 style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)', marginBottom: 12 }}>Quick Connect</h3>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: 16, background: 'rgba(255,255,255,0.06)', borderRadius: 12 }}>
                    <span>Follow Up Boss</span>
                    <button type="button" onClick={() => setShowFUB(true)} style={{ padding: '8px 14px', background: 'var(--accent)', border: 'none', borderRadius: 10, color: 'white', cursor: 'pointer', fontSize: 14 }}>Connect →</button>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: 16, background: 'rgba(255,255,255,0.06)', borderRadius: 12 }}>
                    <span>KVCore</span>
                    <button type="button" onClick={() => setShowKVCore(true)} style={{ padding: '8px 14px', background: 'var(--accent)', border: 'none', borderRadius: 10, color: 'white', cursor: 'pointer', fontSize: 14 }}>Connect →</button>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: 16, background: 'rgba(255,255,255,0.06)', borderRadius: 12 }}>
                    <span>Zapier / Webhooks</span>
                    <button type="button" onClick={() => setShowZapier(true)} style={{ padding: '8px 14px', background: 'var(--accent)', border: 'none', borderRadius: 10, color: 'white', cursor: 'pointer', fontSize: 14 }}>Setup →</button>
                  </div>
                </div>
              </section>

              <section style={{ marginBottom: 24 }}>
                <h3 style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)', marginBottom: 8 }}>Manual Export</h3>
                <p style={{ fontSize: 13, color: 'var(--muted)', marginBottom: 12 }}>Export contacts as CSV.</p>
                <button type="button" onClick={handleExportCsv} disabled={exporting} style={{ width: '100%', padding: 14, background: 'rgba(255,255,255,0.1)', border: '1px solid #333', borderRadius: 12, color: 'var(--accent)', cursor: exporting ? 'not-allowed' : 'pointer', fontSize: 15 }}>Export CSV</button>
              </section>

              <section>
                <h3 style={{ fontSize: 14, fontWeight: 600, color: 'var(--muted)', marginBottom: 8 }}>Webhook (Advanced)</h3>
                <input type="url" value={webhookUrl} onChange={(e) => setWebhookUrl(e.target.value)} placeholder="POST URL" style={{ width: '100%', padding: 12, marginBottom: 8, borderRadius: 10, border: '1px solid #333', background: 'var(--bg-secondary)', color: 'var(--text)' }} />
                <button type="button" onClick={handleTestWebhook} disabled={!webhookUrl.trim() || testingWebhook} style={{ padding: '10px 16px', background: '#007AFF', border: 'none', borderRadius: 10, color: 'white', cursor: 'pointer', fontSize: 14 }}>Test Webhook</button>
                {webhookError && <p style={{ color: 'var(--accent)', marginTop: 8 }}>{webhookError}</p>}
              </section>
            </>
          )}
        </div>
      </div>

      {showFUB && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1001 }}>
          <div style={{ background: 'var(--bg)', borderRadius: 16, maxWidth: 440, width: '90%', border: '1px solid #333' }}>
            <ConnectFUBModal onSuccess={handleFUBSuccess} onCancel={() => setShowFUB(false)} />
          </div>
        </div>
      )}

      {showKVCore && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1001 }}>
          <div style={{ background: 'var(--bg)', borderRadius: 16, maxWidth: 400, width: '90%', padding: 20, border: '1px solid #333' }}>
            <h3 style={{ marginBottom: 16 }}>Connect KVCore</h3>
            <input type="password" value={kvcoreKey} onChange={(e) => setKvcoreKey(e.target.value)} placeholder="API Key" disabled={connectingKVCore} style={{ width: '100%', padding: 12, marginBottom: 12, borderRadius: 10, border: '1px solid #333', background: 'var(--bg-secondary)', color: 'var(--text)' }} />
            {kvcoreError && <p style={{ color: 'var(--accent)', marginBottom: 8 }}>{kvcoreError}</p>}
            <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button type="button" onClick={() => setShowKVCore(false)} disabled={connectingKVCore}>Cancel</button>
              <button type="button" onClick={handleConnectKVCore} disabled={!kvcoreKey.trim() || connectingKVCore}>{connectingKVCore ? 'Connecting...' : 'Connect'}</button>
            </div>
          </div>
        </div>
      )}

      {showZapier && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1001 }}>
          <div style={{ background: 'var(--bg)', borderRadius: 16, maxWidth: 400, width: '90%', padding: 20, border: '1px solid #333' }}>
            <h3 style={{ marginBottom: 16 }}>Connect Zapier</h3>
            <input type="url" value={zapierUrl} onChange={(e) => setZapierUrl(e.target.value)} placeholder="Webhook URL" disabled={connectingZapier} style={{ width: '100%', padding: 12, marginBottom: 12, borderRadius: 10, border: '1px solid #333', background: 'var(--bg-secondary)', color: 'var(--text)' }} />
            {zapierError && <p style={{ color: 'var(--accent)', marginBottom: 8 }}>{zapierError}</p>}
            <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button type="button" onClick={() => setShowZapier(false)} disabled={connectingZapier}>Cancel</button>
              <button type="button" onClick={handleConnectZapier} disabled={!zapierUrl.trim() || connectingZapier}>{connectingZapier ? 'Connecting...' : 'Connect'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
