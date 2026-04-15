import { supabase } from '../supabase'
import type { CRMConnection, UserIntegration, LeadSyncPayload, MondayBoard } from '../types/leads'

const API_BASE = import.meta.env.VITE_FLYR_API_URL?.replace(/\/$/, '') ?? ''

type BoldTrailConnectResponse = {
  connected?: boolean
  disconnected?: boolean
  success?: boolean
  message?: string
  error?: string
  tokenHint?: string
  account?: {
    name?: string | null
    email?: string | null
  } | null
}

/** Fetch FUB connection status from crm_connections. */
export async function fetchFUBConnection(userId: string): Promise<CRMConnection | null> {
  if (!supabase) return null
  const { data, error } = await supabase
    .from('crm_connections')
    .select('*')
    .eq('user_id', userId)
    .eq('provider', 'fub')
    .maybeSingle()
  if (error) throw error
  return data as CRMConnection | null
}

/** Fetch all user integrations (KVCore, Zapier, etc.) from user_integrations. */
export async function fetchUserIntegrations(userId: string): Promise<UserIntegration[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('user_integrations')
    .select('*')
    .eq('user_id', userId)
  if (error) throw error
  return (data ?? []) as UserIntegration[]
}

/** Fetch all CRM connections (e.g. FUB) for user. */
export async function fetchCRMConnections(userId: string): Promise<CRMConnection[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('crm_connections')
    .select('*')
    .eq('user_id', userId)
  if (error) throw error
  return (data ?? []) as CRMConnection[]
}

/** Connect FUB via backend (API key never stored in frontend). */
export async function connectFUB(apiKey: string, accessToken: string): Promise<{ connected: boolean; account?: { name?: string; company?: string }; error?: string }> {
  const url = `${API_BASE}/api/integrations/fub/connect`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ api_key: apiKey.trim() }),
  })
  const json = await res.json()
  if (!res.ok) return { connected: false, error: json.error ?? 'Failed to connect' }
  return json
}

export async function connectBoldTrail(apiToken: string, accessToken: string): Promise<BoldTrailConnectResponse> {
  const url = `${API_BASE}/api/integrations/boldtrail/connect`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ api_token: apiToken.trim() }),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) {
    return {
      connected: false,
      error: json.error ?? 'Failed to save BoldTrail token',
    }
  }
  return json
}

export async function testBoldTrailConnection(
  accessToken: string,
  apiToken?: string
): Promise<BoldTrailConnectResponse> {
  const url = `${API_BASE}/api/integrations/boldtrail/test`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: apiToken?.trim() ? JSON.stringify({ api_token: apiToken.trim() }) : undefined,
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) {
    return {
      success: false,
      error: json.error ?? 'Failed to test BoldTrail connection',
    }
  }
  return json
}

/** Disconnect FUB via backend. */
export async function disconnectFUB(accessToken: string): Promise<void> {
  const url = `${API_BASE}/api/integrations/fub/disconnect`
  for (const method of ['POST', 'DELETE']) {
    const res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${accessToken}` },
    })
    if (res.ok) return
    if (res.status === 405 && method === 'POST') continue
    const json = await res.json().catch(() => ({}))
    throw new Error(json.error ?? json.message ?? 'Failed to disconnect')
  }
}

export async function disconnectBoldTrail(accessToken: string): Promise<void> {
  const url = `${API_BASE}/api/integrations/boldtrail/disconnect`
  for (const method of ['POST', 'DELETE']) {
    const res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${accessToken}` },
    })
    if (res.ok) return
    if (res.status === 405 && method === 'POST') continue
    const json = await res.json().catch(() => ({}))
    throw new Error(json.error ?? json.message ?? 'Failed to disconnect BoldTrail')
  }
}

/** Connect KVCore by upserting api_key into user_integrations. */
export async function connectKVCore(userId: string, apiKey: string): Promise<void> {
  if (!supabase) throw new Error('Supabase not configured')
  const { error } = await supabase.from('user_integrations').upsert(
    {
      user_id: userId,
      provider: 'kvcore',
      api_key: apiKey.trim(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,provider' }
  )
  if (error) throw error
}

/** Connect Zapier by upserting webhook_url into user_integrations. */
export async function connectZapier(userId: string, webhookUrl: string): Promise<void> {
  if (!supabase) throw new Error('Supabase not configured')
  const { error } = await supabase.from('user_integrations').upsert(
    {
      user_id: userId,
      provider: 'zapier',
      webhook_url: webhookUrl.trim(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,provider' }
  )
  if (error) throw error
}

export async function exchangeOAuthCode(
  provider: 'hubspot' | 'monday',
  code: string,
  userId: string,
  accessToken: string
): Promise<void> {
  const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/oauth_exchange`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({
      provider,
      code,
      user_id: userId,
    }),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error ?? 'OAuth exchange failed')
}

export async function fetchMondayBoards(accessToken: string): Promise<{
  boards: MondayBoard[]
  selectedBoardId?: string | null
  selectedBoardName?: string | null
  accountId?: string | null
  accountName?: string | null
}> {
  const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/monday_boards`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({ action: 'list' }),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error ?? 'Failed to load monday boards')
  return json
}

export async function selectMondayBoard(
  boardId: string,
  accessToken: string
): Promise<{ success: boolean; selectedBoardId?: string | null; selectedBoardName?: string | null }> {
  const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/monday_boards`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({
      action: 'select_board',
      board_id: boardId,
    }),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error ?? 'Failed to save monday board')
  return json
}

/** Disconnect a provider from user_integrations (for KVCore, Zapier). */
export async function disconnectUserIntegration(userId: string, provider: string): Promise<void> {
  if (!supabase) throw new Error('Supabase not configured')
  const { error } = await supabase
    .from('user_integrations')
    .delete()
    .eq('user_id', userId)
    .eq('provider', provider)
  if (error) throw error
}

/**
 * Invoke crm_sync Edge Function to sync a lead to connected CRMs.
 * Follow Up Boss remains the native/special-case path; provider-based CRMs flow through crm_sync.
 */
export async function syncLeadToCRM(
  lead: LeadSyncPayload,
  userId: string,
  accessToken: string
): Promise<{ message?: string; synced?: string[]; failed?: Array<{ provider: string; success: boolean; error?: string }> }> {
  if (!supabase) throw new Error('Supabase not configured')
  const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/crm_sync`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      lead,
      user_id: userId,
    }),
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error ?? 'Sync failed')
  return json
}
