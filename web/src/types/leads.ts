/** Field lead status (matches DB enum). */
export type FieldLeadStatus = 'not_home' | 'interested' | 'qr_scanned' | 'no_answer'

/** Sync status for CRM. */
export type FieldLeadSyncStatus = 'pending' | 'synced' | 'failed'

/** Field lead row from Supabase field_leads table (snake_case from DB). */
export interface FieldLead {
  id: string
  user_id: string
  address: string
  name: string | null
  phone: string | null
  status: FieldLeadStatus
  notes: string | null
  qr_code: string | null
  campaign_id: string | null
  session_id: string | null
  external_crm_id: string | null
  last_synced_at: string | null
  sync_status: FieldLeadSyncStatus | null
  created_at: string
  updated_at: string
}

/** Insert/update payload for field lead (optional fields). */
export interface FieldLeadInsert {
  id?: string
  user_id: string
  address: string
  name?: string | null
  phone?: string | null
  status?: FieldLeadStatus
  notes?: string | null
  qr_code?: string | null
  campaign_id?: string | null
  session_id?: string | null
  external_crm_id?: string | null
  last_synced_at?: string | null
  sync_status?: FieldLeadSyncStatus | null
}

/** CRM connection from crm_connections (FUB status). */
export interface CRMConnection {
  id: string
  user_id: string
  provider: string
  status: 'connected' | 'disconnected' | 'error'
  connected_at: string | null
  last_sync_at: string | null
  metadata: { name?: string | null; company?: string | null } | null
  updated_at: string | null
  error_reason: string | null
}

/** User integration from user_integrations (KVCore, Zapier, etc.). */
export type IntegrationProvider = 'fub' | 'kvcore' | 'hubspot' | 'monday' | 'zapier'

export interface UserIntegration {
  id: string
  user_id: string
  provider: IntegrationProvider
  access_token: string | null
  refresh_token: string | null
  api_key: string | null
  webhook_url: string | null
  expires_at: number | null
  created_at: string
  updated_at: string
}

/** Lead payload for crm_sync Edge Function. */
export interface LeadSyncPayload {
  id: string
  name?: string | null
  phone?: string | null
  email?: string | null
  address?: string | null
  source: string
  campaign_id?: string | null
  notes?: string | null
  created_at: string
}

/** Filters for fetching leads. */
export interface FetchLeadsFilters {
  campaign_id?: string
  session_id?: string
}
