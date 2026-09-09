import type { SupabaseClient } from '@supabase/supabase-js';

type AdminClient = SupabaseClient<any, 'public', any>;

export type ResearchCompany = {
  id: string;
  workspace_id: string;
  name: string;
  website?: string | null;
  website_domain?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  city?: string | null;
  region?: string | null;
  country_code?: string | null;
  google_place_id?: string | null;
  identity_key?: string | null;
  metadata?: Record<string, unknown> | null;
};

type ResearchLead = {
  id: string;
  workspace_id: string;
  company_id?: string | null;
  name: string;
  company?: string | null;
  website?: string | null;
  website_domain?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  city?: string | null;
  region?: string | null;
  country_code?: string | null;
  source?: string | null;
  external_id?: string | null;
  metadata?: Record<string, unknown> | null;
};

function clean(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function normalizeCompanyDomain(value: unknown): string | null {
  const text = clean(value);
  if (!text) return null;
  try {
    const parsed = new URL(text.includes('://') ? text : `https://${text}`);
    return parsed.hostname.toLowerCase().replace(/^www\./, '') || null;
  } catch {
    return text.toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0] || null;
  }
}

function normalizedPart(value: unknown): string {
  return (clean(value) ?? '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function companyIdentityKey(input: { name: unknown; city?: unknown; region?: unknown; address?: unknown }): string {
  const location = normalizedPart(input.city) || normalizedPart(input.address);
  return [normalizedPart(input.name), location, normalizedPart(input.region)].filter(Boolean).join('|').slice(0, 500);
}

function placeIdForLead(lead: ResearchLead): string | null {
  const metadata = lead.metadata && typeof lead.metadata === 'object' ? lead.metadata : {};
  const source = clean(lead.source)?.toLowerCase();
  const metadataSource = clean(metadata.leadSource ?? metadata.source)?.toLowerCase();
  const externalPlaceId = source === 'google_places' || source === 'google-places' || metadataSource === 'places'
    ? clean(lead.external_id)
    : null;
  return clean(metadata.placeId)
    ?? clean(metadata.place_id)
    ?? clean(metadata.googlePlaceId)
    ?? externalPlaceId
    ?? null;
}

async function findCompany(admin: AdminClient, workspaceId: string, input: {
  placeId: string | null;
  domain: string | null;
  identityKey: string;
}): Promise<ResearchCompany | null> {
  if (input.placeId) {
    const { data } = await admin.from('sales_companies').select('*')
      .eq('workspace_id', workspaceId).eq('google_place_id', input.placeId).is('merged_into_id', null).maybeSingle();
    if (data) return data as ResearchCompany;
  }
  if (input.domain) {
    const { data } = await admin.from('sales_companies').select('*')
      .eq('workspace_id', workspaceId).ilike('website_domain', input.domain).is('merged_into_id', null).maybeSingle();
    if (data) return data as ResearchCompany;
  }
  if (input.identityKey) {
    const { data } = await admin.from('sales_companies').select('*')
      .eq('workspace_id', workspaceId).eq('identity_key', input.identityKey).is('merged_into_id', null).limit(1).maybeSingle();
    if (data) return data as ResearchCompany;
  }
  return null;
}

export async function resolveCompanyForLead(
  admin: AdminClient,
  workspaceId: string,
  leadId: string,
  ownerUserId: string
): Promise<ResearchCompany> {
  const { data: rawLead, error: leadError } = await admin.from('sales_leads').select('*')
    .eq('workspace_id', workspaceId).eq('id', leadId).maybeSingle();
  if (leadError) throw leadError;
  if (!rawLead) throw new Error('Sales lead was not found.');
  const lead = rawLead as ResearchLead;

  let linkedCompany: ResearchCompany | null = null;
  if (lead.company_id) {
    const { data } = await admin.from('sales_companies').select('*')
      .eq('workspace_id', workspaceId).eq('id', lead.company_id).is('merged_into_id', null).maybeSingle();
    if (data) linkedCompany = data as ResearchCompany;
  }

  const name = clean(lead.company) ?? clean(lead.name);
  if (!name) throw new Error('Add a company name before researching this lead.');
  const placeId = placeIdForLead(lead);
  const domain = normalizeCompanyDomain(lead.website_domain ?? lead.website);
  const identityKey = companyIdentityKey({ name, city: lead.city, region: lead.region, address: lead.address });
  let company = linkedCompany ?? await findCompany(admin, workspaceId, { placeId, domain, identityKey });
  const leadMetadata = lead.metadata && typeof lead.metadata === 'object' ? lead.metadata : {};

  if (!company) {
    const payload = {
      workspace_id: workspaceId,
      owner_user_id: ownerUserId,
      name,
      website: clean(lead.website),
      website_domain: domain,
      phone: clean(lead.phone),
      email: clean(lead.email)?.toLowerCase() ?? null,
      address: clean(lead.address),
      city: clean(lead.city),
      region: clean(lead.region),
      country_code: clean(lead.country_code)?.toUpperCase() ?? null,
      google_place_id: placeId,
      identity_key: identityKey,
      metadata: { ...leadMetadata, resolvedFromSalesLeadId: lead.id },
    };
    const inserted = await admin.from('sales_companies').insert(payload).select('*').single();
    if (inserted.error) {
      company = await findCompany(admin, workspaceId, { placeId, domain, identityKey });
      if (!company) throw inserted.error;
    } else {
      company = inserted.data as ResearchCompany;
    }
  } else {
    const existingMetadata = company.metadata && typeof company.metadata === 'object' ? company.metadata : {};
    const enriched = await admin.from('sales_companies').update({
      website: clean(company.website) ?? clean(lead.website),
      website_domain: normalizeCompanyDomain(company.website_domain ?? company.website) ?? domain,
      google_place_id: clean(company.google_place_id) ?? placeId,
      metadata: { ...existingMetadata, ...leadMetadata, resolvedFromSalesLeadId: lead.id },
    }).eq('workspace_id', workspaceId).eq('id', company.id).select('*').single();
    if (enriched.error) throw enriched.error;
    company = enriched.data as ResearchCompany;
  }

  const { error: linkError } = await admin.from('sales_leads').update({ company_id: company.id })
    .eq('workspace_id', workspaceId).eq('id', lead.id);
  if (linkError) throw linkError;
  return company;
}

export async function resolveCompanyById(
  admin: AdminClient,
  workspaceId: string,
  companyId: string
): Promise<ResearchCompany> {
  const { data, error } = await admin.from('sales_companies').select('*')
    .eq('workspace_id', workspaceId).eq('id', companyId).is('merged_into_id', null).maybeSingle();
  if (error) throw error;
  if (!data) throw new Error('Company was not found.');
  return data as ResearchCompany;
}

export async function leadIdsForSmartList(
  admin: AdminClient,
  workspaceId: string,
  listId: string,
  userId: string
): Promise<{ listName: string; leadIds: string[] }> {
  const { data: list, error: listError } = await admin.from('smart_lists').select('id,name,criteria')
    .eq('workspace_id', workspaceId).eq('created_by_user_id',userId).eq('id', listId).maybeSingle();
  if (listError) throw listError;
  if (!list) throw new Error('List was not found.');
  const criteria = list.criteria && typeof list.criteria === 'object' ? list.criteria as Record<string, unknown> : {};
  const values = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && Boolean(item)) : [];
  const masterIds = new Set(values(criteria.masterLeadIds ?? criteria.master_lead_ids));
  const contactIds = new Set(values(criteria.contactIds ?? criteria.contact_ids));
  const { data: leads, error: leadsError } = await admin.from('sales_leads')
    .select('id,list_id,sales_contact_id,contact_id,legacy_contact_id')
    .eq('workspace_id', workspaceId).eq('assigned_user_id',userId).limit(5000);
  if (leadsError) throw leadsError;
  const leadIds = (leads ?? []).filter((lead) =>
    lead.list_id === listId || masterIds.has(lead.id)
      || Boolean(lead.sales_contact_id && contactIds.has(lead.sales_contact_id))
      || Boolean(lead.contact_id && contactIds.has(lead.contact_id))
      || Boolean(lead.legacy_contact_id && contactIds.has(lead.legacy_contact_id))
  ).map((lead) => String(lead.id));
  return { listName: String(list.name || 'Created list'), leadIds };
}
