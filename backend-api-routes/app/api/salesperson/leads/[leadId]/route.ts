import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import {
  resolveWorkspaceIdForUser,
  type MinimalSupabaseClient,
} from '@/app/api/_utils/workspace';
import { createAdminClient } from '@/lib/supabase/server';
import { normalizePhoneNumber, phoneMarketFromCountryCode } from '@/lib/dialer/phone';
import type { SalesLead } from '@/types/database';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const LEAD_SELECT = 'id, workspace_id, sales_contact_id, assigned_user_id, assigned_sales_rep_id, created_by_user_id, name, company, phone, phone_e164, email, email_normalized, list_id, list_name, website, website_domain, address, city, region, country_code, source, lead_state, disposition, notes, metadata, created_at, updated_at';

type SalespersonRow = {
  id: string;
  workspace_id: string | null;
};

function clean(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

async function resolveSalesperson(
  admin: ReturnType<typeof createAdminClient>,
  userId: string
): Promise<SalespersonRow | null> {
  const { data, error } = await admin
    .from('salespeople')
    .select('id, workspace_id')
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
    .select('is_founder')
    .eq('user_id', userId)
    .limit(1)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return Boolean((data as { is_founder?: boolean | null } | null)?.is_founder);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ leadId: string }> }
) {
  const requestUser = await resolveUserFromRequest(request);
  if (!requestUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const admin = createAdminClient();
  try {
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const { leadId } = await params;
    const requestedWorkspaceId = clean(body.workspaceId) ?? request.nextUrl.searchParams.get('workspaceId');
    const [salesperson, isFounder] = await Promise.all([
      resolveSalesperson(admin, requestUser.id),
      isFounderUser(admin, requestUser.id),
    ]);
    if (!salesperson && !isFounder) {
      return NextResponse.json({ error: 'Salesperson access is required.' }, { status: 403 });
    }

    const resolution = await resolveWorkspaceIdForUser(
      admin as unknown as MinimalSupabaseClient,
      requestUser.id,
      requestedWorkspaceId
    );
    const workspaceId = resolution.workspaceId ?? salesperson?.workspace_id ?? null;
    if (!workspaceId) return NextResponse.json({ error: 'Workspace not found.' }, { status: 404 });

    let accessibleLead = admin
      .from('sales_leads')
      .select(LEAD_SELECT)
      .eq('workspace_id', workspaceId)
      .eq('id', leadId)
      .limit(1);
    accessibleLead = accessibleLead.eq('assigned_user_id', requestUser.id);
    const { data: existing, error: existingError } = await accessibleLead.maybeSingle();
    if (existingError) throw new Error(existingError.message);
    if (!existing) return NextResponse.json({ error: 'Lead not found.' }, { status: 404 });

    const before = existing as SalesLead;
    const updates: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if ('name' in body) updates.name = clean(body.name) ?? 'Unnamed lead';
    if ('company' in body) updates.company = clean(body.company);
    if ('notes' in body) updates.notes = clean(body.notes);

    if ('email' in body) {
      const email = clean(body.email)?.toLowerCase() ?? null;
      if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return NextResponse.json({ error: 'Enter a valid email address.' }, { status: 400 });
      }
      updates.email = email;
      updates.email_normalized = email;
    }

    if ('phone' in body) {
      const phone = clean(body.phone);
      if (phone) {
        const normalized = normalizePhoneNumber(phone, phoneMarketFromCountryCode(before.country_code));
        if (!normalized.isValid || !normalized.e164) {
          return NextResponse.json({ error: normalized.error ?? 'Enter a valid phone number.' }, { status: 400 });
        }
        updates.phone = phone;
        updates.phone_e164 = normalized.e164;
        updates.phone_country_code = normalized.countryCode;
        updates.phone_area_code = normalized.areaCode;
        updates.phone_area_label = normalized.areaLabel;
      } else {
        updates.phone = null;
        updates.phone_e164 = null;
        updates.phone_country_code = null;
        updates.phone_area_code = null;
        updates.phone_area_label = null;
      }
    }

    const { data: updated, error: updateError } = await admin
      .from('sales_leads')
      .update(updates)
      .eq('workspace_id', workspaceId)
      .eq('id', leadId)
      .select(LEAD_SELECT)
      .single();
    if (updateError) throw new Error(updateError.message);

    if (before.sales_contact_id) {
      const contactUpdates: Record<string, unknown> = { updated_at: updates.updated_at };
      for (const key of ['name', 'company', 'phone', 'phone_e164', 'email', 'email_normalized']) {
        if (key in updates) contactUpdates[key] = updates[key];
      }
      if (Object.keys(contactUpdates).length > 1) {
        const { error: contactError } = await admin
          .from('sales_contacts')
          .update(contactUpdates)
          .eq('workspace_id', workspaceId)
          .eq('id', before.sales_contact_id);
        if (contactError) throw new Error(contactError.message);
      }
    }

    await admin.from('sales_activities').insert({
      workspace_id: workspaceId,
      sales_lead_id: leadId,
      sales_contact_id: before.sales_contact_id ?? null,
      actor_user_id: requestUser.id,
      activity_type: 'contact_update',
      note: 'Contact details updated from WolfGrid Sales.',
      occurred_at: updates.updated_at,
      metadata: { fields: Object.keys(updates).filter((key) => key !== 'updated_at') },
    });

    return NextResponse.json({ lead: updated });
  } catch (error) {
    console.error('[api/salesperson/leads/:leadId] PATCH error:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Failed to update lead.' },
      { status: 500 }
    );
  }
}
