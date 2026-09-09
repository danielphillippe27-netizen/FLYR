import { createHash, randomBytes, randomInt } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { Resend } from 'resend';
import { createAdminClient } from '@/lib/supabase/server';
import { createZoomMeeting, deleteZoomMeeting, zoomAccessTokenForUser } from '@/lib/zoom';
import { triggerSalesAutomations } from '@/lib/sales-pro/automation-trigger';

export const runtime = 'nodejs';

const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const clean = (value: unknown, max = 500) => typeof value === 'string' && value.trim() ? value.trim().slice(0, max) : null;

async function limited(request: NextRequest) {
  const admin = createAdminClient();
  const ip = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  const ipHash = hash(`${process.env.CRON_SECRET ?? 'wolfgrid'}:${ip}`);
  const since = new Date(Date.now() - 60 * 60_000).toISOString();
  const { count } = await admin.from('sales_public_booking_requests').select('*', { count: 'exact', head: true }).eq('ip_hash', ipHash).gte('occurred_at', since);
  if ((count ?? 0) >= 60) return true;
  await admin.from('sales_public_booking_requests').insert({ ip_hash: ipHash });
  return false;
}

function localParts(date: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return { weekday: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(value.weekday), minute: Number(value.hour) * 60 + Number(value.minute) };
}

export async function GET(request: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  if (await limited(request)) return NextResponse.json({ error: 'Too many requests.' }, { status: 429 });
  const admin = createAdminClient();
  const { slug } = await params;
  const { data: link } = await admin.from('sales_booking_links').select('*,sales_booking_link_members(*)').eq('slug', slug).eq('is_active', true).maybeSingle();
  if (!link) return NextResponse.json({ error: 'Booking link not found.' }, { status: 404 });
  const memberIds = (link.sales_booking_link_members ?? []).filter((member) => member.is_active).map((member) => member.user_id);
  const from = new Date(Math.max(Date.now() + Number(link.minimum_notice_minutes) * 60_000, Date.parse(request.nextUrl.searchParams.get('from') ?? '') || 0));
  const to = new Date(Math.min(from.getTime() + 31 * 86400_000, Date.parse(request.nextUrl.searchParams.get('to') ?? '') || from.getTime() + 14 * 86400_000));
  const [{ data: rules }, { data: overrides }, { data: events }, { data: bookings }, { data: holds }] = await Promise.all([
    admin.from('sales_availability_rules').select('*').in('user_id', memberIds).eq('is_active', true),
    admin.from('sales_availability_overrides').select('*').in('user_id', memberIds).lt('starts_at', to.toISOString()).gt('ends_at', from.toISOString()),
    admin.from('calendar_events').select('user_id,start_at,end_at').in('user_id', memberIds).is('deleted_at', null).lt('start_at', to.toISOString()).gt('end_at', from.toISOString()),
    admin.from('sales_bookings').select('assigned_user_id,starts_at,ends_at').in('assigned_user_id', memberIds).eq('status', 'confirmed').lt('starts_at', to.toISOString()).gt('ends_at', from.toISOString()),
    admin.from('sales_booking_holds').select('assigned_user_id,starts_at,ends_at').in('assigned_user_id', memberIds).is('confirmed_at', null).gt('expires_at', new Date().toISOString()).lt('starts_at', to.toISOString()).gt('ends_at', from.toISOString()),
  ]);
  const busy = [...(events ?? []).map((row) => ({ userId: row.user_id, start: row.start_at, end: row.end_at })), ...(bookings ?? []).map((row) => ({ userId: row.assigned_user_id, start: row.starts_at, end: row.ends_at })), ...(holds ?? []).map((row) => ({ userId: row.assigned_user_id, start: row.starts_at, end: row.ends_at }))];
  const slots: string[] = [];
  for (let timestamp = Math.ceil(from.getTime() / 900_000) * 900_000; timestamp + link.duration_minutes * 60_000 <= to.getTime(); timestamp += 900_000) {
    const start = new Date(timestamp); const end = new Date(timestamp + link.duration_minutes * 60_000);
    const available = memberIds.some((userId) => {
      const userRules = (rules ?? []).filter((rule) => rule.user_id === userId);
      const parts = localParts(start, userRules[0]?.timezone ?? link.timezone);
      const inRule = userRules.some((rule) => rule.weekday === parts.weekday && parts.minute >= rule.start_minute && parts.minute + link.duration_minutes <= rule.end_minute);
      const override = (overrides ?? []).find((row) => row.user_id === userId && Date.parse(row.starts_at) < end.getTime() && Date.parse(row.ends_at) > start.getTime());
      return (override ? override.is_available : inRule) && !busy.some((row) => row.userId === userId && Date.parse(row.start) < end.getTime() && Date.parse(row.end) > start.getTime());
    });
    if (available) slots.push(start.toISOString());
  }
  return NextResponse.json({ link: { slug: link.slug, title: link.title, description: link.description, durationMinutes: link.duration_minutes, timezone: link.timezone }, slots });
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  if (await limited(request)) return NextResponse.json({ error: 'Too many requests.' }, { status: 429 });
  const admin = createAdminClient(); const { slug } = await params; const body = await request.json().catch(() => ({}));
  const guestName = clean(body.name, 200); const guestEmail = clean(body.email, 254)?.toLowerCase(); const guestPhone = clean(body.phone, 40);
  const start = new Date(clean(body.startAt) ?? '');
  const { data: link } = await admin.from('sales_booking_links').select('*').eq('slug', slug).eq('is_active', true).maybeSingle();
  if (!link || !guestName || !guestEmail || !/^\S+@\S+\.\S+$/.test(guestEmail) || Number.isNaN(start.getTime())) return NextResponse.json({ error: 'Valid contact and slot details are required.' }, { status: 400 });
  if (start.getTime() < Date.now() + Number(link.minimum_notice_minutes) * 60_000) return NextResponse.json({ error: 'That slot is no longer available.' }, { status: 409 });
  const end = new Date(start.getTime() + Number(link.duration_minutes) * 60_000); const token = randomBytes(32).toString('base64url'); const code = String(randomInt(100000, 1000000));
  const { data, error } = await admin.rpc('create_sales_booking_hold', { target_link_id: link.id, target_starts_at: start.toISOString(), target_ends_at: end.toISOString(), target_token_hash: hash(token), target_verification_hash: hash(code), target_guest_name: guestName, target_guest_email: guestEmail, target_guest_phone: guestPhone });
  if (error || !data?.[0]) return NextResponse.json({ error: error?.message ?? 'The slot was just taken.' }, { status: 409 });
  const from = process.env.RESEND_FROM_EMAIL?.trim();
  if (!process.env.RESEND_API_KEY || !from) return NextResponse.json({ error: 'Booking email verification is not configured.' }, { status: 503 });
  const sent = await new Resend(process.env.RESEND_API_KEY).emails.send({ from, to: guestEmail, subject: `Verify your ${link.title} booking`, text: `Your WolfGrid booking verification code is ${code}. It expires in 10 minutes.` });
  if (sent.error) { await admin.from('sales_booking_holds').delete().eq('id', data[0].id); return NextResponse.json({ error: 'Verification email could not be sent.' }, { status: 502 }); }
  return NextResponse.json({ holdToken: token, expiresAt: data[0].expires_at, verificationRequired: true }, { status: 201 });
}

export async function PUT(request: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  if (await limited(request)) return NextResponse.json({ error: 'Too many requests.' }, { status: 429 });
  const admin = createAdminClient(); const { slug } = await params; const body = await request.json().catch(() => ({}));
  const token = clean(body.holdToken); const code = clean(body.verificationCode);
  if (!token || !code) return NextResponse.json({ error: 'Hold token and verification code are required.' }, { status: 400 });
  const { data: link } = await admin.from('sales_booking_links').select('*').eq('slug', slug).eq('is_active', true).maybeSingle();
  const { data: hold } = link ? await admin.from('sales_booking_holds').select('*').eq('booking_link_id', link.id).eq('token_hash', hash(token)).gt('expires_at', new Date().toISOString()).is('confirmed_at', null).maybeSingle() : { data: null };
  if (!link || !hold || hold.verification_code_hash !== hash(code)) return NextResponse.json({ error: 'The hold or verification code is invalid.' }, { status: 403 });
  const accessToken = await zoomAccessTokenForUser(admin, hold.assigned_user_id).catch(() => null);
  if (!accessToken) return NextResponse.json({ error: 'The host must connect Zoom before accepting bookings.' }, { status: 409 });
  let zoom: Awaited<ReturnType<typeof createZoomMeeting>> | null = null;
  try {
    zoom = await createZoomMeeting(accessToken, { topic: link.title, startAt: hold.starts_at, durationMinutes: link.duration_minutes, agenda: link.description });
    const email = String(hold.guest_email).toLowerCase(); const phone = clean(hold.guest_phone);
    let { data: contact } = await admin.from('sales_contacts').select('*').eq('workspace_id', link.workspace_id).eq('owner_user_id', hold.assigned_user_id).eq('email_normalized', email).is('merged_into_id', null).maybeSingle();
    if (!contact) { const created = await admin.from('sales_contacts').insert({ workspace_id: link.workspace_id, owner_user_id: hold.assigned_user_id, name: hold.guest_name, email, email_normalized: email, phone, phone_e164: phone, source: 'booking' }).select('*').single(); contact = created.data; }
    let { data: lead } = await admin.from('sales_leads').select('*').eq('workspace_id', link.workspace_id).eq('assigned_user_id', hold.assigned_user_id).eq('sales_contact_id', contact?.id).order('updated_at', { ascending: false }).limit(1).maybeSingle();
    if (!lead) { const created = await admin.from('sales_leads').insert({ workspace_id: link.workspace_id, sales_contact_id: contact?.id, user_id: hold.assigned_user_id, assigned_user_id: hold.assigned_user_id, created_by_user_id: hold.assigned_user_id, name: hold.guest_name, email, email_normalized: email, phone, phone_e164: phone, source: 'booking' }).select('*').single(); lead = created.data; }
    const event = await admin.from('calendar_events').insert({ user_id: hold.assigned_user_id, workspace_id: link.workspace_id, title: link.title, start_at: hold.starts_at, end_at: hold.ends_at, event_type: 'appointment', contact_id: contact?.id, contact_name: hold.guest_name, location: 'Zoom', color_key: 'blue', conference_provider: 'zoom', conference_id: String(zoom.id), conference_join_url: zoom.join_url, attendee_emails: [email] }).select('*').single();
    if (event.error) throw event.error;
    const cancelToken = randomBytes(32).toString('base64url');
    const booking = await admin.from('sales_bookings').insert({ workspace_id: link.workspace_id, booking_link_id: link.id, assigned_user_id: hold.assigned_user_id, sales_contact_id: contact?.id, sales_lead_id: lead?.id, calendar_event_id: event.data.id, guest_name: hold.guest_name, guest_email: email, guest_phone: phone, starts_at: hold.starts_at, ends_at: hold.ends_at, zoom_join_url: zoom.join_url, cancellation_token_hash: hash(cancelToken) }).select('*').single();
    if (booking.error) throw booking.error;
    await admin.from('sales_booking_holds').update({ confirmed_at: new Date().toISOString() }).eq('id', hold.id);
    const { data: meetingStage } = await admin.from('sales_pipeline_stages').select('id').eq('workspace_id', link.workspace_id).eq('stage_key', 'meeting_booked').maybeSingle();
    if (lead && meetingStage) await admin.from('sales_leads').update({ pipeline_stage_id: meetingStage.id, pipeline_stage: 'connected' }).eq('id', lead.id);
    if (lead) await triggerSalesAutomations(admin, { workspaceId: link.workspace_id, triggerType: 'meeting_booked', leadId: lead.id, contactId: contact?.id, ownerUserId: hold.assigned_user_id, context: { bookingId: booking.data.id, stageId: meetingStage?.id } });
    const reminders = (link.reminder_minutes ?? [1440, 60]).flatMap((minutes) => ['email', 'push'].map((channel) => ({ workspace_id: link.workspace_id, booking_id: booking.data.id, channel, scheduled_for: new Date(Date.parse(hold.starts_at) - Number(minutes) * 60_000).toISOString() }))).filter((row) => Date.parse(row.scheduled_for) > Date.now());
    if (reminders.length) await admin.from('sales_booking_reminders').insert(reminders);
    const from = process.env.RESEND_FROM_EMAIL?.trim(); const appUrl = process.env.NEXT_PUBLIC_APP_URL?.replace(/\/$/, '') ?? new URL(request.url).origin;
    if (process.env.RESEND_API_KEY && from) await new Resend(process.env.RESEND_API_KEY).emails.send({ from, to: email, subject: `Confirmed: ${link.title}`, text: `Your meeting is confirmed for ${hold.starts_at}.\n\nJoin Zoom: ${zoom.join_url}\n\nManage booking: ${appUrl}/api/public/bookings/${cancelToken}` });
    return NextResponse.json({ booking: booking.data, joinUrl: zoom.join_url, cancellationToken: cancelToken }, { status: 201 });
  } catch (cause) {
    if (zoom) await deleteZoomMeeting(accessToken, String(zoom.id)).catch(() => undefined);
    return NextResponse.json({ error: cause instanceof Error ? cause.message : 'Booking failed.' }, { status: 502 });
  }
}
