import { useState, useEffect } from 'react'
import { useAuth } from '../contexts/AuthContext'
import {
  fetchCRMConnections,
  fetchUserIntegrations,
  disconnectFUB,
  connectKVCore,
  connectZapier,
  disconnectUserIntegration,
  syncLeadToCRM,
} from '../lib/integrations'
import type { CRMConnection, UserIntegration, IntegrationProvider } from '../types/leads'
import ConnectFUBModal from './ConnectFUBModal'

const PROVIDERS: { id: IntegrationProvider; name: string; description: string }[] = [
  { id: 'fub', name: 'Follow Up Boss', description: 'Real estate CRM and lead management' },
  { id: 'kvcore', name: 'KVCore', description: 'Real estate marketing platform' },
  { id: 'hubspot', name: 'HubSpot', description: 'Marketing, sales, and service platform' },
  { id: 'monday', name: 'Monday.com', description: 'Work management and collaboration' },
  { id: 'zapier', name: 'Zapier / Webhooks', description: 'Automate workflows with webhooks' },
]

export default function IntegrationsPage() {
  const { user, getAccessToken } = useAuth()
  const [connections, setConnections] = useState<CRMConnection[]>([])
  const [integrations, setIntegrations] = useState<UserIntegration[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showFUB, setShowFUB] = useState(false)
  const [showKVCore, setShowKVCore] = useState(false)
  const [showZapier, setShowZapier] = useState(false)
  const [kvcoreKey, setKvcoreKey] = useState('')
  const [zapierUrl, setZapierUrl] = useState('')
  const [apiError, setApiError] = useState<string | null>(null)
  const [connecting, setConnecting] = useState<string | null>(null)
  const [testLeadSent, setTestLeadSent] = useState(false)
  const [sendingTest, setSendingTest] = useState(false)

  async function load() {
    if (!user?.id) return
    setLoading(true)
    setError(null)
    try {
      const [c, i] = await Promise.all([fetchCRMConnections(user.id), fetchUserIntegrations(user.id)])
      setConnections(c)
      setIntegrations(i)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [user?.id])

  function isConnected(provider: IntegrationProvider): boolean {
    if (provider === 'fub') {
      return connections.some((c) => c.provider === 'fub' && c.status === 'connected')
    }
    const int = integrations.find((i) => i.provider === provider)
    if (!int) return false
    if (provider === 'zapier') return !!int.webhook_url
    if (provider === 'kvcore') return !!int.api_key
    return !!int.access_token
  }

  async function handleConnect(provider: IntegrationProvider) {
    if (provider === 'fub') {
      setShowFUB(true)
      return
    }
    if (provider === 'kvcore') {
      setShowKVCore(true)
      return
    }
    if (provider === 'zapier') {
      setShowZapier(true)
      return
    }
    setApiError('HubSpot and Monday require OAuth (not implemented on web yet).')
  }

  async function handleDisconnect(provider: IntegrationProvider) {
    if (!user?.id) return
    setConnecting(provider)
    setApiError(null)
    try {
      if (provider === 'fub') {
        const token = await getAccessToken()
        if (!token) throw new Error('Not signed in')
        await disconnectFUB(token)
      } else {
        await disconnectUserIntegration(user.id, provider)
      }
      await load()
    } catch (e) {
      setApiError(e instanceof Error ? e.message : 'Failed to disconnect')
    } finally {
      setConnecting(null)
    }
  }

  async function handleFUBSuccess() {
    setShowFUB(false)
    await load()
  }

  async function handleConnectKVCore() {
    if (!user?.id || !kvcoreKey.trim()) return
    setConnecting('kvcore')
    setApiError(null)
    try {
      await connectKVCore(user.id, kvcoreKey)
      setShowKVCore(false)
      setKvcoreKey('')
      await load()
    } catch (e) {
      setApiError(e instanceof Error ? e.message : 'Failed to connect')
    } finally {
      setConnecting(null)
    }
  }

  async function handleConnectZapier() {
    if (!user?.id || !zapierUrl.trim()) return
    setConnecting('zapier')
    setApiError(null)
    try {
      await connectZapier(user.id, zapierUrl)
      setShowZapier(false)
      setZapierUrl('')
      await load()
    } catch (e) {
      setApiError(e instanceof Error ? e.message : 'Failed to connect')
    } finally {
      setConnecting(null)
    }
  }

  async function handleSendTestLead() {
    if (!user?.id) return
    const token = await getAccessToken()
    if (!token) return
    setSendingTest(true)
    setApiError(null)
    try {
      await syncLeadToCRM(
        {
          id: crypto.randomUUID(),
          name: 'Test Lead',
          phone: '555-555-5555',
          email: 'test@flyr.app',
          address: '123 Test St',
          source: 'FLYR Test',
          notes: 'This is a test lead from FLYR',
          created_at: new Date().toISOString(),
        },
        user.id,
        token
      )
      setTestLeadSent(true)
      setTimeout(() => setTestLeadSent(false), 3000)
    } catch (e) {
      setApiError(e instanceof Error ? e.message : 'Failed to send test lead')
    } finally {
      setSendingTest(false)
    }
  }

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg)', padding: 20 }}>
      <h1 style={{ fontSize: 28, marginBottom: 24 }}>Integrations</h1>

      {error && (
        <p style={{ color: 'var(--accent)', marginBottom: 16 }}>{error}</p>
      )}
      {apiError && (
        <p style={{ color: 'var(--accent)', marginBottom: 16 }}>{apiError}</p>
      )}

      {loading ? (
        <p style={{ color: 'var(--muted)' }}>Loading...</p>
      ) : (
        <>
          <section style={{ marginBottom: 32 }}>
            <h2 style={{ fontSize: 22, fontWeight: 700, marginBottom: 16 }}>CRM Connections</h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {PROVIDERS.map((p) => {
                const connected = isConnected(p.id)
                return (
                  <div
                    key={p.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 14,
                      padding: 16,
                      background: 'var(--bg-secondary)',
                      borderRadius: 12,
                      border: '1px solid #333',
                    }}
                  >
                    <div style={{ flex: 1 }}>
                      <div style={{ fontWeight: 600, fontSize: 16 }}>{p.name}</div>
                      <div style={{ fontSize: 13, color: 'var(--muted)' }}>{p.description}</div>
                    </div>
                    <button
                      type="button"
                      onClick={() => (connected ? handleDisconnect(p.id) : handleConnect(p.id))}
                      disabled={connecting !== null}
                      style={{
                        padding: '8px 16px',
                        borderRadius: 8,
                        border: 'none',
                        fontSize: 15,
                        fontWeight: 500,
                        cursor: connecting ? 'not-allowed' : 'pointer',
                        background: connected ? 'rgba(255,79,79,0.2)' : '#007AFF',
                        color: connected ? 'var(--accent)' : 'white',
                      }}
                    >
                      {connected ? 'Disconnect' : (p.id === 'zapier' ? 'Setup' : 'Connect') + ' →'}
                    </button>
                  </div>
                )
              })}
            </div>
          </section>

          <section style={{ padding: 16, background: 'var(--bg-secondary)', borderRadius: 20, border: '1px solid #333' }}>
            <h2 style={{ fontSize: 22, fontWeight: 700, marginBottom: 12 }}>Automation</h2>
            <button
              type="button"
              onClick={handleSendTestLead}
              disabled={sendingTest}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: '14px 20px',
                background: '#007AFF',
                border: 'none',
                borderRadius: 12,
                color: 'white',
                fontSize: 17,
                fontWeight: 600,
                cursor: sendingTest ? 'not-allowed' : 'pointer',
              }}
            >
              {testLeadSent ? '✓ Lead sent' : sendingTest ? 'Sending...' : 'Send Test Lead'}
            </button>
            <p style={{ fontSize: 13, color: 'var(--muted)', marginTop: 12 }}>
              Send a test lead to all connected CRMs to verify your integration.
            </p>
          </section>
        </>
      )}

      {showFUB && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
          <div style={{ background: 'var(--bg)', borderRadius: 16, maxWidth: 440, width: '90%', border: '1px solid #333' }}>
            <ConnectFUBModal onSuccess={handleFUBSuccess} onCancel={() => setShowFUB(false)} />
          </div>
        </div>
      )}

      {showKVCore && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
          <div style={{ background: 'var(--bg)', borderRadius: 16, maxWidth: 400, width: '90%', padding: 20, border: '1px solid #333' }}>
            <h3 style={{ marginBottom: 16 }}>Connect KVCore</h3>
            <input
              type="password"
              value={kvcoreKey}
              onChange={(e) => setKvcoreKey(e.target.value)}
              placeholder="API Key"
              disabled={!!connecting}
              style={{ width: '100%', padding: 12, marginBottom: 12, borderRadius: 10, border: '1px solid #333', background: 'var(--bg-secondary)', color: 'var(--text)' }}
            />
            <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button type="button" onClick={() => setShowKVCore(false)} disabled={!!connecting}>Cancel</button>
              <button type="button" onClick={handleConnectKVCore} disabled={!kvcoreKey.trim() || !!connecting}>{connecting === 'kvcore' ? 'Connecting...' : 'Connect'}</button>
            </div>
          </div>
        </div>
      )}

      {showZapier && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
          <div style={{ background: 'var(--bg)', borderRadius: 16, maxWidth: 400, width: '90%', padding: 20, border: '1px solid #333' }}>
            <h3 style={{ marginBottom: 16 }}>Connect Zapier</h3>
            <input
              type="url"
              value={zapierUrl}
              onChange={(e) => setZapierUrl(e.target.value)}
              placeholder="Webhook URL"
              disabled={!!connecting}
              style={{ width: '100%', padding: 12, marginBottom: 12, borderRadius: 10, border: '1px solid #333', background: 'var(--bg-secondary)', color: 'var(--text)' }}
            />
            <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button type="button" onClick={() => setShowZapier(false)} disabled={!!connecting}>Cancel</button>
              <button type="button" onClick={handleConnectZapier} disabled={!zapierUrl.trim() || !!connecting}>{connecting === 'zapier' ? 'Connecting...' : 'Connect'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
