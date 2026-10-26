import { loadActivityLogs } from '@/lib/dialer/activity-log';
import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { NextRequest, NextResponse } from 'next/server';
import { clampLimit, cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const contactId = cleanText(request.nextUrl.searchParams.get('contactId'));
  const leadId = cleanText(request.nextUrl.searchParams.get('leadId'));
  if (!contactId && !leadId) return NextResponse.json({ error: 'contactId or leadId is required.' }, { status: 400 });
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, {contactId,leadId}); }
  catch { return NextResponse.json({error:'Linked record not found.'},{status:404}); }
  const limit = clampLimit(request.nextUrl.searchParams.get('limit'), 25, 100);
  const offset = Math.max(0, Math.min(10000, Math.floor(Number(request.nextUrl.searchParams.get('offset')) || 0)));
  try {
    return NextResponse.json(await loadActivityLogs(context, { leadId, contactId }, limit, offset), { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) {
    console.error('[crm/timeline]', error);
    return NextResponse.json({ error: 'Unable to load activity logs. Please try again.' }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const note = cleanText(body.note);
  if (!note) return NextResponse.json({ error: 'Note is required.' }, { status: 400 });
  try { await requirePersonalReferences(context.admin,context.workspaceId,context.userId,{contactId:cleanText(body.contactId),leadId:cleanText(body.leadId)}); }
  catch { return NextResponse.json({error:'Linked record not found.'},{status:404}); }
  const { data, error } = await context.admin.from('sales_activities').insert({
    workspace_id: context.workspaceId, sales_contact_id: cleanText(body.contactId), sales_lead_id: cleanText(body.leadId),
    actor_user_id: context.userId, activity_type: 'note', note, occurred_at: new Date().toISOString(), metadata: {},
  }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ activity: data }, { status: 201 });
}
