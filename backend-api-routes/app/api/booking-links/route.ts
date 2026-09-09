import { randomBytes } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

function slug(value: unknown) {
  return (cleanText(value) ?? randomBytes(8).toString('hex')).toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-|-$/g, '').slice(0, 80);
}

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const { data, error } = await context.admin.from('sales_booking_links').select('*,sales_booking_link_members(*)').eq('workspace_id', context.workspaceId).or(`owner_user_id.eq.${context.userId},mode.eq.round_robin`).order('created_at', { ascending: false });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const links = (data ?? []).filter(link => link.owner_user_id === context.userId || (
    link.mode === 'round_robin' && (context.role === 'owner' || context.role === 'admin' ||
      (link.sales_booking_link_members ?? []).some(member => member.user_id === context.userId))
  ));
  return NextResponse.json({ links });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const title = cleanText(body.title);
  const mode = body.mode === 'round_robin' ? 'round_robin' : 'personal';
  if (!title) return NextResponse.json({ error: 'Title is required.' }, { status: 400 });
  if (mode === 'round_robin' && context.role !== 'owner' && context.role !== 'admin') return NextResponse.json({ error: 'Admin access is required for team links.' }, { status: 403 });
  const members = mode === 'round_robin' && Array.isArray(body.memberUserIds) ? [...new Set(body.memberUserIds.filter((id): id is string => typeof id === 'string'))] : [context.userId];
  if (!members.length) return NextResponse.json({ error: 'At least one booking member is required.' }, { status: 400 });
  const { data: eligible, error: memberError } = await context.admin.from('workspace_members').select('user_id')
    .eq('workspace_id', context.workspaceId).in('user_id', members);
  if (memberError) return NextResponse.json({ error: 'Unable to validate booking members.' }, { status: 500 });
  const eligibleIds = new Set((eligible ?? []).map(member => member.user_id));
  if (members.some(id => !eligibleIds.has(id))) return NextResponse.json({ error: 'Booking members must belong to this workspace.' }, { status: 403 });
  const { data, error } = await context.admin.from('sales_booking_links').insert({
    workspace_id: context.workspaceId, owner_user_id: mode === 'personal' ? context.userId : null,
    slug: slug(body.slug), title, description: cleanText(body.description), mode,
    duration_minutes: Math.min(240, Math.max(10, Number(body.durationMinutes) || 30)), timezone: cleanText(body.timezone) ?? 'UTC',
    minimum_notice_minutes: Math.max(0, Number(body.minimumNoticeMinutes) || 60), reminder_minutes: Array.isArray(body.reminderMinutes) ? body.reminderMinutes : [1440, 60],
  }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  await context.admin.from('sales_booking_link_members').insert(members.map((userId, position) => ({ booking_link_id: data.id, user_id: userId, position })));
  for (const userId of members.filter(id => id === context.userId)) {
    const { count } = await context.admin.from('sales_availability_rules').select('*', { count: 'exact', head: true }).eq('workspace_id', context.workspaceId).eq('user_id', userId);
    if ((count ?? 0) === 0) await context.admin.from('sales_availability_rules').insert([1, 2, 3, 4, 5].map((weekday) => ({ workspace_id: context.workspaceId, user_id: userId, weekday, start_minute: 540, end_minute: 1020, timezone: cleanText(body.timezone) ?? 'UTC' })));
  }
  return NextResponse.json({ link: data }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const id = cleanText(body.id);
  if (!id) return NextResponse.json({ error: 'Link id is required.' }, { status: 400 });
  const { data: existing, error: lookupError } = await context.admin.from('sales_booking_links').select('id,mode,owner_user_id')
    .eq('workspace_id', context.workspaceId).eq('id', id).maybeSingle();
  if (lookupError) return NextResponse.json({ error: 'Unable to load booking link.' }, { status: 500 });
  const canEdit = existing && (existing.owner_user_id === context.userId ||
    (existing.mode === 'round_robin' && (context.role === 'owner' || context.role === 'admin')));
  if (!canEdit) return NextResponse.json({ error: 'Booking link not found.' }, { status: 404 });
  const updates: Record<string, unknown> = {};
  if (cleanText(body.title)) updates.title = cleanText(body.title);
  if (typeof body.isActive === 'boolean') updates.is_active = body.isActive;
  if (Number(body.durationMinutes)) updates.duration_minutes = Math.min(240, Math.max(10, Number(body.durationMinutes)));
  const { data, error } = await context.admin.from('sales_booking_links').update(updates).eq('workspace_id', context.workspaceId).eq('id', id).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ link: data });
}
