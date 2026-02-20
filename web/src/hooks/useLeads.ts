import { useState, useCallback, useEffect } from 'react'
import { fetchLeads } from '../lib/fieldLeads'
import { fetchCRMConnections } from '../lib/integrations'
import { fetchUserIntegrations } from '../lib/integrations'
import { supabase } from '../supabase'
import type { FieldLead } from '../types/leads'
import type { CRMConnection } from '../types/leads'
import type { UserIntegration } from '../types/leads'

export function useLeads(userId: string | undefined, workspaceId?: string | null) {
  const [leads, setLeads] = useState<FieldLead[]>([])
  const [searchText, setSearchText] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [connections, setConnections] = useState<CRMConnection[]>([])
  const [integrations, setIntegrations] = useState<UserIntegration[]>([])

  const load = useCallback(async () => {
    if (!userId) return
    setLoading(true)
    setError(null)
    try {
      const [leadsData, conns, ints] = await Promise.all([
        fetchLeads(userId, undefined, workspaceId),
        fetchCRMConnections(userId),
        fetchUserIntegrations(userId),
      ])
      setLeads(leadsData)
      setConnections(conns)
      setIntegrations(ints)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load leads')
    } finally {
      setLoading(false)
    }
  }, [userId, workspaceId])

  useEffect(() => {
    load()
  }, [load])

  // Realtime: refetch when contacts change so web list stays in sync
  useEffect(() => {
    if (!supabase || (!userId && !workspaceId)) return
    const filter = workspaceId ? `workspace_id=eq.${workspaceId}` : `user_id=eq.${userId}`
    const channel = supabase
      .channel('contacts_changes')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'contacts',
          filter,
        },
        () => {
          load()
        }
      )
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [userId, workspaceId, load])

  const hasConnectedCRM =
    connections.some((c) => c.status === 'connected') ||
    integrations.some((i) =>
      i.provider === 'zapier' ? !!i.webhook_url : i.provider === 'fub' || i.provider === 'kvcore' ? !!i.api_key : !!i.access_token
    )

  const filteredLeads = !searchText.trim()
    ? leads
    : leads.filter((l) => {
        const q = searchText.toLowerCase()
        return (
          l.address.toLowerCase().includes(q) ||
          (l.name?.toLowerCase().includes(q) ?? false) ||
          (l.phone?.toLowerCase().includes(q) ?? false)
        )
      })

  return {
    leads: filteredLeads,
    allLeads: leads,
    setLeads,
    searchText,
    setSearchText,
    loading,
    error,
    load,
    connections,
    integrations,
    hasConnectedCRM,
  }
}
