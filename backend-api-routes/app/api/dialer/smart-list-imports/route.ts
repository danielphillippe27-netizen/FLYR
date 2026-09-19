import { NextRequest, NextResponse } from 'next/server';
import { getDialerRequestContext, type DialerRequestContext } from '@/lib/dialer/server';
import type { SalesLead } from '@/types/database';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type SmartListRow = {
  id: string;
  name: string;
  criteria: Record<string, unknown> | null;
  created_at: string;
};

function clean(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function strings(value: unknown): string[] {
  return Array.isArray(value) ? value.map(clean).filter((item): item is string => Boolean(item)) : [];
}

function leadListMetadata(lead: SalesLead): { id: string | null; name: string | null } {
  const metadata = lead.metadata && typeof lead.metadata === 'object' ? lead.metadata : {};
  return {
    id: clean(lead.list_id) ?? clean(metadata.listId) ?? clean(metadata.list_id),
    name: clean(lead.list_name) ?? clean(metadata.listName) ?? clean(metadata.list_name),
  };
}

function scopeLeadQuery(query: any, context: DialerRequestContext) {
  return query.eq('assigned_user_id', context.requestUser.id);
}

function importLead(lead: SalesLead, listId: string, listName: string) {
  return {
    name: clean(lead.name) ?? 'Lead',
    phone: clean(lead.phone_e164) ?? clean(lead.phone) ?? '',
    company: clean(lead.company),
    email: clean(lead.email),
    list_id: listId,
    list_name: listName,
  };
}

export async function GET(request: NextRequest) {
  const context = await getDialerRequestContext(request, request.nextUrl.searchParams.get('workspaceId'));
  if (context instanceof NextResponse) return context;

  try {
    let leadQuery = context.admin
      .from('sales_leads')
      .select('*')
      .eq('workspace_id', context.workspaceId)
      .order('created_at', { ascending: false })
      .limit(5000);
    leadQuery = scopeLeadQuery(leadQuery, context);

    const [leadResult, listResult] = await Promise.all([
      leadQuery,
      context.admin
        .from('smart_lists')
        .select('id,name,criteria,created_at')
        .eq('created_by_user_id',context.requestUser.id)
        .eq('workspace_id', context.workspaceId)
        .order('created_at', { ascending: false })
        .limit(1000),
    ]);
    if (leadResult.error) throw leadResult.error;
    if (listResult.error) {
      console.warn('[dialer/smart-list-imports] smart_lists lookup failed; using lead metadata', listResult.error);
    }

    const leads = (leadResult.data ?? []) as SalesLead[];
    const smartLists = (listResult.data ?? []) as SmartListRow[];
    const lists = new Map<string, { id: string; name: string; createdAt: string; leads: SalesLead[] }>();

    for (const list of smartLists) {
      const criteria = list.criteria && typeof list.criteria === 'object' ? list.criteria : {};
      const masterLeadIds = new Set(strings(criteria.masterLeadIds ?? criteria.master_lead_ids));
      const contactIds = new Set(strings(criteria.contactIds ?? criteria.contact_ids));
      const matching = leads.filter((lead) => {
        const metadata = leadListMetadata(lead);
        return metadata.id === list.id
          || masterLeadIds.has(lead.id)
          || Boolean(lead.sales_contact_id && contactIds.has(lead.sales_contact_id))
          || Boolean(lead.contact_id && contactIds.has(lead.contact_id))
          || Boolean(lead.legacy_contact_id && contactIds.has(lead.legacy_contact_id));
      });
      lists.set(list.id, {
        id: list.id,
        name: clean(list.name) ?? 'Created list',
        createdAt: list.created_at,
        leads: matching,
      });
    }

    for (const lead of leads) {
      const metadata = leadListMetadata(lead);
      if (!metadata.name) continue;
      const id = metadata.id ?? `named:${metadata.name.toLowerCase()}`;
      const existing = lists.get(id);
      if (existing) {
        if (!existing.leads.some((candidate) => candidate.id === lead.id)) existing.leads.push(lead);
      } else {
        lists.set(id, {
          id,
          name: metadata.name,
          createdAt: lead.created_at,
          leads: [lead],
        });
      }
    }

    const shaped = [...lists.values()]
      .map((list) => {
        const uniqueLeads = [...new Map(list.leads.map((lead) => [lead.id, lead])).values()];
        const importable = uniqueLeads.map((lead) => importLead(lead, list.id, list.name));
        const dialableCount = importable.filter((lead) => lead.phone.replace(/\D/g, '').length >= 8).length;
        return {
          id: list.id,
          name: list.name,
          description: 'Your list · available on iOS and web',
          count: uniqueLeads.length,
          dialableCount,
          leads: importable,
          createdAt: list.createdAt,
        };
      })
      .sort((left, right) => right.createdAt.localeCompare(left.createdAt));

    return NextResponse.json({ lists: shaped, workspaceId: context.workspaceId });
  } catch (error) {
    console.error('[dialer/smart-list-imports]', error);
    return NextResponse.json({ error: 'Failed to load created lists.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const context = await getDialerRequestContext(request, clean(body.workspaceId));
  if (context instanceof NextResponse) return context;

  const name = clean(body.name);
  if (!name) return NextResponse.json({ error: 'List name is required.' }, { status: 400 });

  try {
    const { data, error } = await context.admin
      .from('smart_lists')
      .insert({
        workspace_id: context.workspaceId,
        created_by_user_id: context.requestUser.id,
        name,
        criteria: {
          baseKind: 'custom',
          source: '',
          tags: [],
          campaignIds: [],
          farmIds: [],
          contactIds: [],
          masterLeadIds: [],
        },
      })
      .select('id,name,created_at')
      .single();
    if (error || !data) throw error ?? new Error('List was not created');

    return NextResponse.json({
      list: {
        id: String(data.id),
        name: String(data.name),
        description: 'New shared workspace list',
        count: 0,
        dialableCount: 0,
        leads: [],
      },
    }, { status: 201 });
  } catch (error) {
    console.error('[dialer/smart-list-imports] create', error);
    return NextResponse.json({ error: 'Failed to create list.' }, { status: 500 });
  }
}
