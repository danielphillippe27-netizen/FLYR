import { NextRequest, NextResponse } from 'next/server';
import { getDialerRequestContext, type DialerRequestContext } from '@/lib/dialer/server';
import { ensureSalespersonLeadMaster } from '@/lib/sales-leads/master-list';
import type { DiallerLeadDisposition, SalesLead, SalesLeadState } from '@/types/database';

import { sendManagedEmail } from '@/lib/sales-pro/communications';
import { SALES_DEMO_URL } from '@/lib/email/demo';
import { DEMO_EMAIL_DOMAIN, DEMO_EMAIL_HANDLE_PATTERN, normalizeDemoEmailHandle } from '@/lib/dialer/demo-email-handle';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const ACTIVE_QUEUE_STATES: SalesLeadState[] = ['new', 'assigned', 'queued', 'attempting', 'no_answer', 'callback'];
const VALID_DISPOSITIONS = new Set<DiallerLeadDisposition>(['interested', 'callback', 'not_now', 'dnc']);

type Context = DialerRequestContext;

function clean(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function listMetadata(row: SalesLead) {
  const metadata = row.metadata && typeof row.metadata === 'object'
    ? row.metadata as Record<string, unknown>
    : {};
  return {
    listId: clean(row.list_id) ?? clean(metadata.listId) ?? clean(metadata.list_id),
    listName: clean(row.list_name) ?? clean(metadata.listName) ?? clean(metadata.list_name),
  };
}

function shapeLead(row: SalesLead) {
  const list = listMetadata(row);
  const metadata = row.metadata && typeof row.metadata === 'object'
    ? row.metadata as Record<string, unknown>
    : {};
  return {
    ...row,
    user_id: row.assigned_user_id ?? row.created_by_user_id,
    name: clean(row.name) ?? 'Lead',
    phone: clean(row.phone_e164) ?? clean(row.phone) ?? '',
    company: clean(row.company),
    role: clean(metadata.role) ?? clean(metadata.jobTitle) ?? clean(metadata.job_title) ?? clean(metadata.title),
    email: clean(row.email),
    timezone: clean(metadata.timezone) ?? clean(metadata.timeZone) ?? clean(metadata.time_zone),
    list_id: list.listId,
    list_name: list.listName,
    called_at: row.last_attempted_at ?? null,
    last_contacted_at: row.last_touch_at ?? row.last_attempted_at ?? null,
    is_starred: row.is_starred === true,
  };
}

function scopeQuery(query: any, context: Context) {
  return query.eq('assigned_user_id', context.requestUser.id);
}

async function loadLead(context: Context, id: string): Promise<SalesLead | null> {
  let query = context.admin
    .from('sales_leads')
    .select('*')
    .eq('workspace_id', context.workspaceId)
    .eq('id', id);
  query = scopeQuery(query, context);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  return (data as SalesLead | null) ?? null;
}

export async function GET(request: NextRequest) {
  const context = await getDialerRequestContext(request, request.nextUrl.searchParams.get('workspaceId'));
  if (context instanceof NextResponse) return context;

  try {
    const focusedIds = (request.nextUrl.searchParams.get('leadIds') ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean)
      .slice(0, 500);

    let query = context.admin
      .from('sales_leads')
      .select('*')
      .eq('workspace_id', context.workspaceId)
      .order('created_at', { ascending: false })
      .limit(2000);
    query = scopeQuery(query, context);
    query = focusedIds.length > 0
      ? query.in('id', focusedIds).neq('lead_state', 'archived')
      : query.in('lead_state', ACTIVE_QUEUE_STATES);

    const { data, error } = await query;
    if (error) throw error;

    return NextResponse.json({
      leads: ((data ?? []) as SalesLead[]).map(shapeLead),
      focusedLeadIds: focusedIds,
      resolvedWorkspaceId: context.workspaceId,
      workspaceId: context.workspaceId,
    });
  } catch (error) {
    console.error('[dialer/leads] GET', error);
    return NextResponse.json({ error: 'Failed to load dialler leads.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const context = await getDialerRequestContext(request, clean(body.workspaceId));
  if (context instanceof NextResponse) return context;

  const rows = Array.isArray(body.leads) ? body.leads.slice(0, 500) : [];
  if (rows.length === 0) {
    return NextResponse.json({ error: 'Add at least one lead.' }, { status: 400 });
  }

  try {
    const imported: ReturnType<typeof shapeLead>[] = [];
    for (const candidate of rows) {
      const lead = candidate && typeof candidate === 'object' ? candidate as Record<string, unknown> : {};
      const phone = clean(lead.phone);
      if (!phone) continue;
      const listId = clean(lead.listId) ?? clean(lead.list_id);
      const listName = clean(lead.listName) ?? clean(lead.list_name);
      const result = await ensureSalespersonLeadMaster(context.admin, {
        workspaceId: context.workspaceId,
        assignedUserId: context.requestUser.id,
        assignedSalespersonId: context.salesperson?.id ?? null,
        createdByUserId: context.requestUser.id,
        name: clean(lead.name) ?? 'Lead',
        company: clean(lead.company),
        phone,
        email: clean(lead.email),
        source: 'dialler_import',
        state: 'queued',
        metadata: { listId, listName },
      });
      if (result.row) imported.push(shapeLead(result.row));
    }

    return NextResponse.json({
      leads: imported,
      importedCount: imported.length,
      workspaceId: context.workspaceId,
    });
  } catch (error) {
    console.error('[dialer/leads] POST', error);
    return NextResponse.json({ error: 'Failed to import dialler leads.' }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const context = await getDialerRequestContext(request, clean(body.workspaceId));
  if (context instanceof NextResponse) return context;

  const id = clean(body.id);
  if (!id) return NextResponse.json({ error: 'Lead id is required.' }, { status: 400 });

  try {
    const existing = await loadLead(context, id);
    if (!existing) return NextResponse.json({ error: 'Dialler lead not found.' }, { status: 404 });

    const disposition = clean(body.disposition) as DiallerLeadDisposition | null;
    if (disposition && !VALID_DISPOSITIONS.has(disposition)) {
      return NextResponse.json({ error: 'Choose a valid lead status.' }, { status: 400 });
    }

    if (body.sendDemoEmail === true) {
      const recipient = 'email' in body ? clean(body.email) : existing.email;
      if (!recipient || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient)) {
        return NextResponse.json({ error: 'Add a valid email before sending the demo.' }, { status: 400 });
      }
      if (existing.disposition === 'dnc' || existing.lead_state === 'dnc') {
        return NextResponse.json({ error: 'This lead is marked do not contact.' }, { status: 400 });
      }
    }

    const updates: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (typeof body.isStarred === 'boolean') updates.is_starred = body.isStarred;
    if (typeof body.is_starred === 'boolean') updates.is_starred = body.is_starred;
    if ('notes' in body) updates.notes = clean(body.notes);
    if ('email' in body) {
      const email = clean(body.email)?.toLowerCase() ?? null;
      updates.email = email;
      updates.email_normalized = email;
    }
    if (disposition) {
      updates.disposition = disposition;
      updates.lead_state = disposition === 'interested'
        ? 'interested'
        : disposition === 'callback'
          ? 'callback'
          : disposition === 'dnc'
            ? 'dnc'
            : 'not_now';
      updates.pipeline_stage = disposition === 'interested'
        ? 'connected'
        : disposition === 'callback'
          ? 'nurture'
          : 'lost';
    }
    if ('followUpAt' in body || 'follow_up_at' in body) {
      updates.next_follow_up_at = clean(body.followUpAt) ?? clean(body.follow_up_at);
    }

    const { data, error } = await context.admin
      .from('sales_leads')
      .update(updates)
      .eq('id', existing.id)
      .eq('workspace_id', context.workspaceId)
      .select('*')
      .single();
    if (error) throw error;

    let warning: string | null = null;
    if ('email' in body && existing.sales_contact_id) {
      const email = clean(body.email)?.toLowerCase() ?? null;
      const { error: contactEmailError } = await context.admin
        .from('sales_contacts')
        .update({ email, email_normalized: email, updated_at: new Date().toISOString() })
        .eq('workspace_id', context.workspaceId)
        .eq('id', existing.sales_contact_id);
      if (contactEmailError) {
        console.warn('[dialer/leads] contact email enrichment failed', contactEmailError.message);
        warning = 'The dialler email was saved, but the linked contact could not be updated.';
      }
    }

    if (body.sendDemoEmail === true) {
      try {
        const handle = normalizeDemoEmailHandle(context.salesperson?.demo_email_handle);
        await sendManagedEmail({
          admin: context.admin, workspaceId: context.workspaceId, userId: context.requestUser.id,
          contactId: data.sales_contact_id, leadId: data.id, to: data.email,
          subject: 'Your WolfGrid demo', body: `Watch the WolfGrid demo: ${SALES_DEMO_URL}`,
          demo: {
            recipientName: data.name, senderName: context.salesperson?.full_name,
            senderAddress: handle && DEMO_EMAIL_HANDLE_PATTERN.test(handle) ? `${handle}@${DEMO_EMAIL_DOMAIN}` : null,
            replyTo: context.salesperson?.demo_email_reply_to,
          },
        });
      } catch (sendError) {
        console.error('[dialer/leads] demo email failed', sendError);
        return NextResponse.json({ lead: shapeLead(data as SalesLead), error: 'Contact saved, but the demo email could not be confirmed. Check your Inbox before retrying.', demoEmailSent: false }, { status: 502 });
      }
    }

    return NextResponse.json({ lead: shapeLead(data as SalesLead), warning, demoEmailSent: body.sendDemoEmail === true });
  } catch (error) {
    console.error('[dialer/leads] PATCH', error);
    return NextResponse.json({ error: 'Failed to update dialler lead.' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const context = await getDialerRequestContext(request, clean(body.workspaceId));
  if (context instanceof NextResponse) return context;

  const id = clean(body.id);
  const deleteAll = body.deleteAll === true;
  if (!deleteAll && !id) {
    return NextResponse.json({ error: 'Lead id is required.' }, { status: 400 });
  }

  // An explicit selection must never fall back to clearing the entire queue.
  const hasSelection = 'ids' in body;
  if (deleteAll && hasSelection && (!Array.isArray(body.ids) || body.ids.some(
    (value) => typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.trim())
  ))) {
    return NextResponse.json({ error: 'Choose valid lead IDs to remove.' }, { status: 400 });
  }

  try {
    if (deleteAll) {
      const ids = Array.isArray(body.ids)
        ? Array.from(new Set((body.ids as string[]).map((value) => value.trim())))
        : [];
      if (hasSelection && ids.length === 0) return NextResponse.json({ deletedCount: 0 });

      let query = scopeQuery(context.admin
        .from('sales_leads')
        .update({ lead_state: 'archived', updated_at: new Date().toISOString() }, { count: 'exact' })
        .eq('workspace_id', context.workspaceId), context);
      query = hasSelection ? query.in('id', ids) : query.in('lead_state', ACTIVE_QUEUE_STATES);
      const { count, error } = await query;
      if (error) throw error;
      return NextResponse.json({ deletedCount: count ?? 0 });
    }

    const existing = await loadLead(context, id);
    if (!existing) return NextResponse.json({ deletedCount: 0 });
    const { error } = await context.admin
      .from('sales_leads')
      .update({ lead_state: 'archived', updated_at: new Date().toISOString() })
      .eq('id', existing.id)
      .eq('workspace_id', context.workspaceId);
    if (error) throw error;
    return NextResponse.json({ deletedCount: 1 });
  } catch (error) {
    console.error('[dialer/leads] DELETE', error);
    return NextResponse.json({ error: 'Failed to remove dialler lead.' }, { status: 500 });
  }
}
