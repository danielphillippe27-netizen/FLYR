import { supabase } from '../supabase'
import type { FieldLead, FieldLeadInsert, FetchLeadsFilters } from '../types/leads'

type ContactStatus = 'new' | 'hot' | 'warm' | 'cold'

interface ContactRow {
  id: string
  user_id: string
  full_name: string
  phone: string | null
  email: string | null
  address: string
  campaign_id: string | null
  status: ContactStatus
  notes: string | null
  created_at: string
  updated_at: string
}

function toFieldLeadStatus(status: ContactStatus): FieldLead['status'] {
  switch (status) {
    case 'hot':
      return 'interested'
    case 'warm':
      return 'qr_scanned'
    case 'cold':
      return 'no_answer'
    case 'new':
    default:
      return 'not_home'
  }
}

function toContactStatus(status: FieldLeadInsert['status'] | undefined): ContactStatus {
  switch (status) {
    case 'interested':
      return 'hot'
    case 'qr_scanned':
      return 'warm'
    case 'no_answer':
      return 'cold'
    case 'not_home':
    default:
      return 'new'
  }
}

function mapContactToFieldLead(row: ContactRow): FieldLead {
  return {
    id: row.id,
    user_id: row.user_id,
    address: row.address,
    name: row.full_name || null,
    phone: row.phone,
    email: row.email,
    status: toFieldLeadStatus(row.status),
    notes: row.notes,
    qr_code: null,
    campaign_id: row.campaign_id,
    session_id: null,
    external_crm_id: null,
    last_synced_at: null,
    sync_status: null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  }
}

export async function fetchLeads(
  userId: string,
  filters?: FetchLeadsFilters
): Promise<FieldLead[]> {
  if (!supabase) return []
  let query = supabase
    .from('contacts')
    .select('id,user_id,full_name,phone,email,address,campaign_id,status,notes,created_at,updated_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
  if (filters?.campaign_id) query = query.eq('campaign_id', filters.campaign_id)
  const { data, error } = await query
  if (error) throw error
  return ((data ?? []) as ContactRow[]).map(mapContactToFieldLead)
}

export async function addLead(lead: FieldLeadInsert): Promise<FieldLead> {
  if (!supabase) throw new Error('Supabase not configured')
  const row = {
    id: lead.id,
    user_id: lead.user_id,
    full_name: lead.name?.trim() || 'Lead',
    phone: lead.phone ?? null,
    email: lead.email ?? null,
    address: lead.address,
    campaign_id: lead.campaign_id ?? null,
    status: toContactStatus(lead.status),
    notes: lead.notes ?? null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }
  const { data, error } = await supabase
    .from('contacts')
    .insert(row)
    .select('id,user_id,full_name,phone,email,address,campaign_id,status,notes,created_at,updated_at')
    .single()
  if (error) throw error
  return mapContactToFieldLead(data as ContactRow)
}

export async function updateLead(id: string, updates: Partial<FieldLeadInsert>): Promise<FieldLead> {
  if (!supabase) throw new Error('Supabase not configured')
  const updateRow: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  }
  if (updates.name !== undefined) updateRow.full_name = updates.name?.trim() || 'Lead'
  if (updates.phone !== undefined) updateRow.phone = updates.phone
  if (updates.email !== undefined) updateRow.email = updates.email
  if (updates.address !== undefined) updateRow.address = updates.address
  if (updates.campaign_id !== undefined) updateRow.campaign_id = updates.campaign_id
  if (updates.status !== undefined) updateRow.status = toContactStatus(updates.status)
  if (updates.notes !== undefined) updateRow.notes = updates.notes

  const { data, error } = await supabase
    .from('contacts')
    .update(updateRow)
    .eq('id', id)
    .select('id,user_id,full_name,phone,email,address,campaign_id,status,notes,created_at,updated_at')
    .single()
  if (error) throw error
  return mapContactToFieldLead(data as ContactRow)
}

export async function deleteLead(id: string): Promise<void> {
  if (!supabase) throw new Error('Supabase not configured')
  const { error } = await supabase.from('contacts').delete().eq('id', id)
  if (error) throw error
}

export async function fetchLeadById(id: string): Promise<FieldLead | null> {
  if (!supabase) return null
  const { data, error } = await supabase
    .from('contacts')
    .select('id,user_id,full_name,phone,email,address,campaign_id,status,notes,created_at,updated_at')
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  if (!data) return null
  return mapContactToFieldLead(data as ContactRow)
}
