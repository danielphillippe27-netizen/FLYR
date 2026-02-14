import { supabase } from '../supabase'
import type { CRMConnection, UserIntegration, LeadSyncPayload } from '../types/leads'

const API_BASE = import.meta.env.VITE_FLYR_API_URL?.replace(/\/$/, '') ?? ''

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

/** Disconnect FUB via backend. */
export async function disconnectFUB(accessToken: string): Promise<void> {
  const url = `${API_BASE}/api/integrations/fub/disconnect`
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!res.ok) {
    const json = await res.json().catch(() => ({}))
    throw new Error(json.error ?? 'Failed to disconnect')
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
 * Note: FUB keys connected via backend are stored in crm_connection_secrets; the Edge Function
 * currently reads user_integrations. So FUB sync works when the user connected FUB via the
 * Integrations page (backend), only if the Edge Function is updated to resolve FUB from
 * crm_connection_secrets, or when FUB is stored in user_integrations (e.g. legacy).
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
    body: JSON.stringify({ lead, user_id: userId }),
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error ?? 'Sync failed')
  return json
}
