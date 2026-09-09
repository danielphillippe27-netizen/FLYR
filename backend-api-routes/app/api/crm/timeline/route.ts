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
  const limit = clampLimit(request.nextUrl.searchParams.get('limit'), 100, 300);
  let activities = context.admin.from('sales_activities').select('*').eq('workspace_id', context.workspaceId).eq('actor_user_id', context.userId).order('occurred_at', { ascending: false }).limit(limit);
  let communications = context.admin.from('communication_events').select('*').eq('workspace_id', context.workspaceId).eq('actor_user_id', context.userId).order('occurred_at', { ascending: false }).limit(limit);
  let tasks = context.admin.from('sales_tasks').select('*').eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).order('created_at', { ascending: false }).limit(limit);
  let bookings = context.admin.from('sales_bookings').select('*').eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId).order('created_at', { ascending: false }).limit(limit);
  let campaigns = context.admin.from('sales_contact_campaigns').select('created_at,campaign_id').eq('workspace_id', context.workspaceId).order('created_at', { ascending: false }).limit(limit);
  if (contactId) { activities = activities.eq('sales_contact_id', contactId); communications = communications.eq('sales_contact_id', contactId); tasks = tasks.eq('sales_contact_id', contactId); bookings = bookings.eq('sales_contact_id', contactId); campaigns = campaigns.eq('sales_contact_id', contactId); }
  if (leadId) { activities = activities.eq('sales_lead_id', leadId); communications = communications.eq('sales_lead_id', leadId); tasks = tasks.eq('sales_lead_id', leadId); bookings = bookings.eq('sales_lead_id', leadId); campaigns = campaigns.eq('sales_contact_id', '00000000-0000-0000-0000-000000000000'); }
  const [activityResult, communicationResult, taskResult, bookingResult, campaignResult] = await Promise.all([activities, communications, tasks, bookings, campaigns]);
  if (activityResult.error || communicationResult.error || taskResult.error || bookingResult.error || campaignResult.error) return NextResponse.json({ error: activityResult.error?.message ?? communicationResult.error?.message ?? taskResult.error?.message ?? bookingResult.error?.message ?? campaignResult.error?.message }, { status: 500 });
  const campaignIds = (campaignResult.data ?? []).map(item => item.campaign_id);
  const ownedCampaigns = campaignIds.length ? await context.admin.from('campaigns').select('id,name,title').eq('owner_id',context.userId).eq('workspace_id',context.workspaceId).in('id',campaignIds) : {data:[],error:null};
  if (ownedCampaigns.error) return NextResponse.json({error:ownedCampaigns.error.message},{status:500});
  const campaignById = new Map((ownedCampaigns.data ?? []).map(item => [item.id,item]));
  const timeline = [
    ...(activityResult.data ?? []).map((item) => ({ ...item, timelineKind: 'activity', at: item.occurred_at })),
    ...(communicationResult.data ?? []).map((item) => ({ ...item, timelineKind: 'communication', at: item.occurred_at })),
    ...(taskResult.data ?? []).map((item) => ({ ...item, timelineKind: 'task', activity_type: item.status === 'completed' ? 'task_completed' : 'task_created', note: item.title, occurred_at: item.completed_at ?? item.created_at, at: item.completed_at ?? item.created_at })),
    ...(bookingResult.data ?? []).map((item) => ({ ...item, timelineKind: 'meeting', activity_type: item.outcome ? `meeting_${item.outcome}` : 'meeting_booked', note: `${item.guest_name} · ${item.starts_at}`, occurred_at: item.created_at, at: item.created_at })),
    ...(campaignResult.data ?? []).filter(item => campaignById.has(item.campaign_id)).map((item) => {
      const campaign = campaignById.get(item.campaign_id);
      return { ...item, id: `${contactId}:campaign:${campaign?.id ?? item.created_at}`, timelineKind: 'campaign', activity_type: 'campaign_added', note: campaign?.name ?? campaign?.title ?? 'Campaign', occurred_at: item.created_at, at: item.created_at };
    }),
  ].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, limit);
  return NextResponse.json({ timeline });
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
