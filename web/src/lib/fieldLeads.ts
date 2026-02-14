import { supabase } from '../supabase'
import type { FieldLead, FieldLeadInsert, FetchLeadsFilters } from '../types/leads'

export async function fetchLeads(
  userId: string,
  filters?: FetchLeadsFilters
): Promise<FieldLead[]> {
  if (!supabase) return []
  let query = supabase
    .from('field_leads')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
  if (filters?.campaign_id) query = query.eq('campaign_id', filters.campaign_id)
  if (filters?.session_id) query = query.eq('session_id', filters.session_id)
  const { data, error } = await query
  if (error) throw error
  return (data ?? []) as FieldLead[]
}

export async function addLead(lead: FieldLeadInsert): Promise<FieldLead> {
  if (!supabase) throw new Error('Supabase not configured')
  const row = {
    ...lead,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }
  const { data, error } = await supabase
    .from('field_leads')
    .insert(row)
    .select()
    .single()
  if (error) throw error
  return data as FieldLead
}

export async function updateLead(id: string, updates: Partial<FieldLeadInsert>): Promise<FieldLead> {
  if (!supabase) throw new Error('Supabase not configured')
  const { data, error } = await supabase
    .from('field_leads')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as FieldLead
}

export async function deleteLead(id: string): Promise<void> {
  if (!supabase) throw new Error('Supabase not configured')
  const { error } = await supabase.from('field_leads').delete().eq('id', id)
  if (error) throw error
}
