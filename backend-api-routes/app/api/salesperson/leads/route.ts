import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import {
  resolveWorkspaceIdForUser,
  type MinimalSupabaseClient,
} from '@/app/api/_utils/workspace';
import { createAdminClient } from '@/lib/supabase/server';
import { ensureSalespersonLeadMaster } from '@/lib/sales-leads/master-list';
import type { SalesLead } from '@/types/database';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type SalespersonRow = {
  id: string;
  full_name: string;
  email: string;
  workspace_id: string | null;
};

type LeadListResponse = {
  leads: SalesLead[];
  workspaceId: string | null;
};

function readString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function withListMetadata(row: SalesLead): SalesLead {
  const metadata = row.metadata && typeof row.metadata === 'object'
    ? row.metadata as Record<string, unknown>
    : {};

  return {
    ...row,
    list_id: readString(row.list_id) ?? readString(metadata.listId) ?? readString(metadata.list_id),
    list_name: readString(row.list_name) ?? readString(metadata.listName) ?? readString(metadata.list_name),
  };
}

async function resolveSalesperson(
  admin: ReturnType<typeof createAdminClient>,
  userId: string
): Promise<SalespersonRow | null> {

  const { data, error } = await admin
    .from('salespeople')
    .select('id, full_name, email, workspace_id')
    .eq('user_id', userId)
    .eq('status', 'active')
    .limit(1)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return (data as SalespersonRow | null) ?? null;
}

async function isFounderUser(
  admin: ReturnType<typeof createAdminClient>,
  userId: string
): Promise<boolean> {
  const { data, error } = await admin
    .from('user_profiles')
    .select('user_id, is_founder')
    .eq('user_id', userId)
    .limit(1)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return Boolean((data as { is_founder?: boolean | null } | null)?.is_founder);
}

async function resolveWorkspaceIdForLeads(params: {
  admin: ReturnType<typeof createAdminClient>;
  requestUser: { id: string };
  salesperson: SalespersonRow | null;
  requestedWorkspaceId?: string | null;
}): Promise<string | null> {
  if (params.requestedWorkspaceId) {
    const requestedResolution = await resolveWorkspaceIdForUser(
      params.admin as unknown as MinimalSupabaseClient,
      params.requestUser.id,
      params.requestedWorkspaceId
    );
    if (requestedResolution.workspaceId) return requestedResolution.workspaceId;
  }

  if (params.salesperson?.workspace_id) return params.salesperson.workspace_id;

  const resolution = await resolveWorkspaceIdForUser(
    params.admin as unknown as MinimalSupabaseClient,
    params.requestUser.id,
    params.requestedWorkspaceId ?? null
  );

  return resolution.workspaceId;
}

async function linkLeadToSalesContact(
  admin: ReturnType<typeof createAdminClient>,
  lead: SalesLead,
  ownerUserId: string
): Promise<{ lead: SalesLead; created: boolean }> {
  if (lead.sales_contact_id) return { lead, created: false };

  const leadMetadata = lead.metadata && typeof lead.metadata === 'object'
    ? lead.metadata as Record<string, unknown>
    : {};
  const now = new Date().toISOString();
  const { data: contact, error: contactError } = await admin
    .from('sales_contacts')
    .insert({
      workspace_id: lead.workspace_id,
      sales_rep_id: lead.assigned_sales_rep_id ?? null,
      user_id: ownerUserId,
      owner_user_id: ownerUserId,
      name: lead.name,
      company: lead.company ?? null,
      phone: lead.phone ?? null,
      phone_e164: lead.phone_e164 ?? null,
      email: lead.email ?? null,
      email_normalized: lead.email_normalized ?? null,
      website: lead.website ?? null,
      website_domain: lead.website_domain ?? null,
      address: lead.address ?? null,
      city: lead.city ?? null,
      region: lead.region ?? null,
      country_code: lead.country_code ?? null,
      source: lead.source ?? 'manual',
      external_id: lead.external_id ?? null,
      metadata: {
        ...leadMetadata,
        createdFrom: 'sales-lead-conversion',
        salesLeadId: lead.id,
        ...(lead.list_id ? { sourceListId: lead.list_id } : {}),
        ...(lead.list_name ? { sourceListName: lead.list_name } : {}),
      },
      updated_at: now,
    })
    .select('id')
    .single();
  if (contactError || !contact?.id) {
    throw new Error(contactError?.message ?? 'Failed to create contact.');
  }

  const { data: linkedLead, error: linkError } = await admin
    .from('sales_leads')
    .update({ sales_contact_id: contact.id, updated_at: now })
    .eq('workspace_id', lead.workspace_id)
    .eq('id', lead.id)
    .is('sales_contact_id', null)
    .select('*')
    .maybeSingle();

  if (linkError || !linkedLead) {
    await admin.from('sales_contacts').delete().eq('id', contact.id);
    if (!linkError) {
      const { data: refreshed } = await admin
        .from('sales_leads')
        .select('*')
        .eq('workspace_id', lead.workspace_id)
        .eq('id', lead.id)
        .maybeSingle();
      if (refreshed?.sales_contact_id) return { lead: refreshed as SalesLead, created: false };
    }
    throw new Error(linkError?.message ?? 'Failed to link the contact to this lead.');
  }

  await admin.from('sales_activities').insert({
    workspace_id: lead.workspace_id,
    sales_lead_id: lead.id,
    sales_contact_id: contact.id,
    actor_user_id: ownerUserId,
    activity_type: 'contact_created',
    note: 'Contact created from lead list.',
    occurred_at: now,
    metadata: { source: 'explicit_create_contact' },
  });

  return { lead: linkedLead as SalesLead, created: true };
}

export async function GET(request: NextRequest) {
  const requestUser = await resolveUserFromRequest(request);
  if (!requestUser) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const admin = createAdminClient();
  const requestedWorkspaceId = request.nextUrl.searchParams.get('workspaceId');

  try {
    const [salesperson, isFounder] = await Promise.all([
      resolveSalesperson(admin, requestUser.id),
      isFounderUser(admin, requestUser.id),
    ]);

    if (!salesperson && !isFounder) {
      return NextResponse.json(
        { error: 'Salesperson access is required for the leads list.' },
        { status: 403 }
      );
    }

    const workspaceId = await resolveWorkspaceIdForLeads({
      admin,
      requestUser,
      salesperson,
      requestedWorkspaceId,
    });

    if (!workspaceId) {
      return NextResponse.json({ leads: [], workspaceId: null } satisfies LeadListResponse);
    }

    let query = admin
      .from('sales_leads')
      .select(
        'id, workspace_id, sales_contact_id, converted_contact_id, legacy_contact_id, legacy_dialler_lead_id, legacy_master_lead_id, assigned_user_id, assigned_sales_rep_id, created_by_user_id, name, company, phone, phone_e164, email, email_normalized, list_id, list_name, website, website_domain, address, city, region, country_code, source, external_id, lead_fingerprint, lead_state, attempt_count, last_attempted_at, next_follow_up_at, follow_up_name, demo_link_follow_up_id, disposition, is_starred, notes, metadata, created_at, updated_at'
      )
      .eq('workspace_id', workspaceId)
      .order('created_at', { ascending: false });

    query = query.eq('assigned_user_id', requestUser.id);

    const { data, error } = await query.limit(2000);
    if (error) throw error;

    return NextResponse.json({
      leads: ((data ?? []) as SalesLead[]).map(withListMetadata),
      workspaceId,
    } satisfies LeadListResponse);
  } catch (error) {
    console.error('[api/salesperson/leads] GET error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Failed to load salesperson leads.' },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  const requestUser = await resolveUserFromRequest(request);
  if (!requestUser) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const admin = createAdminClient();

  try {
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const sourceLeadId = readString(body.leadId);
    const name = readString(body.name);
    if (!sourceLeadId && !name) {
      return NextResponse.json({ error: 'Name is required.' }, { status: 400 });
    }

    const email = readString(body.email)?.toLowerCase() ?? null;
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return NextResponse.json({ error: 'Enter a valid email address.' }, { status: 400 });
    }
    const firstName = readString(body.firstName);
    const lastName = readString(body.lastName);
    const company = readString(body.company);
    const photoPath = readString(body.photoPath);

    const requestedWorkspaceId = readString(body.workspaceId);
    const [salesperson, isFounder] = await Promise.all([
      resolveSalesperson(admin, requestUser.id),
      isFounderUser(admin, requestUser.id),
    ]);
    if (!salesperson && !isFounder) {
      return NextResponse.json(
        { error: 'Salesperson access is required to create a contact.' },
        { status: 403 }
      );
    }

    const workspaceId = await resolveWorkspaceIdForLeads({
      admin,
      requestUser,
      salesperson,
      requestedWorkspaceId,
    });
    if (!workspaceId) {
      return NextResponse.json({ error: 'Workspace not found.' }, { status: 404 });
    }

    if (sourceLeadId) {
      let leadQuery = admin
        .from('sales_leads')
        .select('*')
        .eq('workspace_id', workspaceId)
        .eq('id', sourceLeadId)
        .limit(1);
      leadQuery = leadQuery.eq('assigned_user_id', requestUser.id);
      const { data: sourceLead, error: sourceLeadError } = await leadQuery.maybeSingle();
      if (sourceLeadError) throw sourceLeadError;
      if (!sourceLead) {
        return NextResponse.json({ error: 'Lead not found.' }, { status: 404 });
      }

      const linked = await linkLeadToSalesContact(admin, sourceLead as SalesLead, requestUser.id);
      return NextResponse.json(
        { lead: withListMetadata(linked.lead), created: linked.created },
        { status: linked.created ? 201 : 200 }
      );
    }

    const submittedMetadata = {
      createdFrom: 'wolfgrid-sales-ios',
      ...(firstName ? { firstName } : {}),
      ...(lastName ? { lastName } : {}),
      ...(photoPath ? { photoPath } : {}),
    };
    const result = await ensureSalespersonLeadMaster(admin, {
      workspaceId,
      assignedUserId: requestUser.id,
      assignedSalespersonId: salesperson?.id ?? null,
      createdByUserId: requestUser.id,
      name: name!,
      company,
      phone: readString(body.phone),
      email,
      address: readString(body.address),
      source: 'manual',
      state: 'assigned',
      notes: readString(body.notes),
      metadata: submittedMetadata,
    });

    if (!result.row) {
      return NextResponse.json(
        { error: result.warning ?? 'Failed to create contact.' },
        { status: 500 }
      );
    }

    if (result.row.assigned_user_id !== requestUser.id) {
      return NextResponse.json(
        { error: 'A matching contact is already assigned to another salesperson.' },
        { status: 409 }
      );
    }

    let responseLead = result.row;
    if (!result.created && (company || firstName || lastName || photoPath)) {
      const existingMetadata = result.row.metadata && typeof result.row.metadata === 'object'
        ? result.row.metadata as Record<string, unknown>
        : {};
      const existingPhotoPath = readString(existingMetadata.photoPath);
      const mergedMetadata = {
        ...existingMetadata,
        createdFrom: 'wolfgrid-sales-ios',
        ...(firstName ? { firstName } : {}),
        ...(lastName ? { lastName } : {}),
        ...(existingPhotoPath
          ? { photoPath: existingPhotoPath }
          : photoPath
            ? { photoPath }
            : {}),
      };
      const { data: updatedLead, error: updateError } = await admin
        .from('sales_leads')
        .update({
          ...(company ? { company } : {}),
          metadata: mergedMetadata,
        })
        .eq('id', result.row.id)
        .eq('assigned_user_id', requestUser.id)
        .select('*')
        .single();
      if (updateError) throw updateError;
      responseLead = updatedLead as SalesLead;
    }

    const linked = await linkLeadToSalesContact(admin, responseLead, requestUser.id);
    return NextResponse.json(
      { lead: withListMetadata(linked.lead), created: linked.created },
      { status: linked.created ? 201 : 200 }
    );
  } catch (error) {
    console.error('[api/salesperson/leads] POST error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Failed to create contact.' },
      { status: 500 }
    );
  }
}
