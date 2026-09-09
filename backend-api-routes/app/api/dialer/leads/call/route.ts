import { NextRequest, NextResponse } from 'next/server';
import type { DialerCall, DialerSession, DialerSessionLead, DiallerLead } from '@/types/database';
import { getDialerRequestContext, type DialerRequestContext } from '@/lib/dialer/server';
import { getDialerTelecomProvider } from '@/lib/dialer/env';
import { resolveOutboundCallerId } from '@/lib/dialer/caller-id';
import { normalizePhoneNumber, phoneMarketFromCountryCode } from '@/lib/dialer/phone';
import { incrementMasterLeadAttemptForDiallerLead } from '@/lib/sales-leads/master-list';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type DiallerLeadCallPayload = {
  workspaceId?: string;
  leadId?: string;
  phone?: string;
  label?: string;
  tabId?: string;
  doubleDial?: boolean;
};

function cleanText(value: string | null | undefined): string {
  return (value ?? '').trim();
}

function normalizeDiallerLeadPhone(lead: DiallerLead) {
  return normalizePhoneNumber(
    cleanText(lead.phone_e164) || lead.phone,
    phoneMarketFromCountryCode(lead.phone_country_code)
  );
}

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as DiallerLeadCallPayload;
  const manualPhone = cleanText(body.phone);

  if (!body.leadId && !manualPhone) {
    return NextResponse.json({ error: 'leadId or phone is required.' }, { status: 400 });
  }

  const context = await getDialerRequestContext(request, body.workspaceId);
  if (context instanceof NextResponse) return context;

  let diallerLead: DiallerLead | null = null;
  if (body.leadId) {
    let leadQuery = context.admin
      .from('sales_leads')
      .select('*')
      .eq('id', body.leadId)
      .eq('workspace_id', context.workspaceId);

    leadQuery = leadQuery.eq('assigned_user_id', context.requestUser.id);

    const { data: lead, error: leadError } = await leadQuery.maybeSingle();

    if (leadError) {
      console.error('[dialer/leads/call] failed to load dialler lead', leadError);
      return NextResponse.json({ error: 'Failed to load dialler lead.' }, { status: 500 });
    }

    if (!lead) {
      return NextResponse.json({ error: 'Dialler lead not found.' }, { status: 404 });
    }

    diallerLead = lead as DiallerLead;
  }

  const normalized = diallerLead
    ? normalizeDiallerLeadPhone(diallerLead)
    : normalizePhoneNumber(manualPhone);
  if (!normalized.isValid || !normalized.e164) {
    return NextResponse.json({ error: normalized.error ?? 'Phone number is invalid.' }, { status: 400 });
  }

  const callLabel = diallerLead
    ? cleanText(diallerLead.name) || 'Lead'
    : cleanText(body.label) || normalized.national || normalized.e164;

  const now = new Date().toISOString();
  const { data: session, error: sessionError } = await context.admin
    .from('dialer_sessions')
    .insert({
      workspace_id: context.workspaceId,
      user_id: context.requestUser.id,
      name: diallerLead
        ? (body.doubleDial ? 'Founder Dialler Double Dial' : 'Founder Dialler')
        : 'Manual Dialler',
      status: 'active',
      source_filter: diallerLead
        ? {
            source: 'sales_leads',
            dialler_lead_id: diallerLead.id,
            sales_lead_id: diallerLead.id,
            double_dial: body.doubleDial === true,
          }
        : {
            source: 'manual',
            phone: normalized.e164,
          },
      started_at: now,
      tab_id: body.tabId?.trim() || null,
    })
    .select('*')
    .single();

  if (sessionError || !session) {
    console.error('[dialer/leads/call] failed to create session', sessionError);
    return NextResponse.json({ error: 'Failed to create dialler session.' }, { status: 500 });
  }

  const { data: sessionLead, error: sessionLeadError } = await context.admin
    .from('dialer_session_leads')
    .insert({
      session_id: session.id,
      workspace_id: context.workspaceId,
      contact_id: null,
      sales_lead_id: diallerLead?.id ?? null,
      position: 1,
      status: 'calling',
      attempt_count: 1,
      updated_at: now,
    })
    .select('*')
    .single();

  if (sessionLeadError || !sessionLead) {
    console.error('[dialer/leads/call] failed to create session lead', sessionLeadError);
    return NextResponse.json({ error: 'Failed to create dialler queue item.' }, { status: 500 });
  }

  const callRequestId = crypto.randomUUID();
  const telecomProvider = getDialerTelecomProvider();
  const fromNumber = resolveOutboundCallerId({
    toNumber: normalized.e164,
    defaultFromNumber: context.settings.defaultFromNumber,
    allowMarketOverride: !context.settings.salespersonFromNumber,
  });
  const { data: call, error: callError } = await context.admin
    .from('dialer_calls')
    .insert({
      workspace_id: context.workspaceId,
      session_id: session.id,
      session_lead_id: sessionLead.id,
      contact_id: null,
      sales_lead_id: diallerLead?.id ?? null,
      user_id: context.requestUser.id,
      call_request_id: callRequestId,
      telecom_provider: telecomProvider,
      to_number_raw: diallerLead?.phone ?? manualPhone,
      to_number_e164: normalized.e164,
      from_number_e164: fromNumber,
      status: 'pending',
      direction: 'outbound',
      status_payload: {
        diallerLeadId: diallerLead?.id ?? null,
        diallerLeadName: callLabel,
        diallerLeadPhone: cleanText(diallerLead?.phone) || manualPhone,
        diallerLeadEmail: cleanText(diallerLead?.email) || null,
        diallerLeadCompany: cleanText(diallerLead?.company) || null,
        manualCall: diallerLead === null,
        destinationCountryCode: normalized.countryCode,
        destinationAreaCode: normalized.areaCode,
        destinationAreaLabel: normalized.areaLabel,
        salespersonId: context.salesperson?.id ?? null,
        doubleDial: body.doubleDial === true,
        contentRetention: 'pending',
      },
    })
    .select('*')
    .single();

  if (callError || !call) {
    console.error('[dialer/leads/call] failed to create call', callError);
    return NextResponse.json({ error: 'Failed to start outbound call.' }, { status: 500 });
  }

  const activeCall = call as DialerCall;

  await context.admin
    .from('dialer_session_leads')
    .update({ last_call_id: activeCall.id, updated_at: now })
    .eq('id', sessionLead.id);

  if (diallerLead) {
    await incrementMasterLeadAttemptForDiallerLead(
      context.admin,
      diallerLead,
      now,
      context.salesperson?.id ?? null
    );
  }

  return NextResponse.json({
    call: activeCall,
    contact: null,
    session: session as DialerSession,
    sessionLead: sessionLead as DialerSessionLead,
  });
}
