import type { SalesLead } from '@/types/database';

export type SavedLeadList = { id: string; name: string; createdAt: string; leadIds: string[] };
export type LeadListGroup = { id: string; title: string; newestAt: string; leads: SalesLead[] };

/** List membership survives a newer list tag, conversion to a contact, or queue archival. */
export function mergeSavedListMembership(
  fallbackGroups: LeadListGroup[],
  savedLists: SavedLeadList[],
  leads: SalesLead[],
): LeadListGroup[] {
  const groups = new Map(fallbackGroups.map((group) => [group.id, group]));
  const byId = new Map(leads.map((lead) => [lead.id, lead]));
  for (const saved of savedLists) {
    const fallback = groups.get(saved.id);
    const members = new Map((fallback?.leads ?? []).map((lead) => [lead.id, lead]));
    for (const id of saved.leadIds ?? []) {
      const lead = byId.get(id);
      if (lead) members.set(id, lead);
    }
    groups.set(saved.id, {
      id: saved.id, title: saved.name, newestAt: saved.createdAt || fallback?.newestAt || '',
      leads: [...members.values()].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at)),
    });
  }
  return [...groups.values()].sort((a, b) => Date.parse(b.newestAt) - Date.parse(a.newestAt));
}
