import { createHash } from 'crypto';
import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { createZoomMeeting, deleteZoomMeeting, zoomAccessTokenForUser } from '@/lib/zoom';

const hash = (value: string) => createHash('sha256').update(value).digest('hex');

async function bookingFor(token: string) {
  const admin = createAdminClient();
  const { data } = await admin.from('sales_bookings').select('*,sales_booking_links(*)').eq('cancellation_token_hash', hash(token)).maybeSingle();
  return { admin, booking: data };
}

export async function GET(_request: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params; const { booking } = await bookingFor(token);
  if (!booking) return NextResponse.json({ error: 'Booking not found.' }, { status: 404 });
  return NextResponse.json({ booking: { guestName: booking.guest_name, startsAt: booking.starts_at, endsAt: booking.ends_at, status: booking.status, joinUrl: booking.zoom_join_url } });
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params; const { admin, booking } = await bookingFor(token);
  if (!booking) return NextResponse.json({ error: 'Booking not found.' }, { status: 404 });
  if (booking.calendar_event_id) {
    const {data:event,error}=await admin.from('calendar_events').select('id').eq('id',booking.calendar_event_id).eq('user_id',booking.assigned_user_id).eq('workspace_id',booking.workspace_id).maybeSingle();
    if (error) return NextResponse.json({error:'Calendar lookup failed.'},{status:500});
    if (!event) return NextResponse.json({error:'Booking calendar is unavailable.'},{status:409});
  }
  const {error:cancelError}=await admin.from('sales_bookings').update({ status: 'cancelled', outcome: 'cancelled' }).eq('id', booking.id).eq('assigned_user_id',booking.assigned_user_id).eq('workspace_id',booking.workspace_id);
  if (cancelError) return NextResponse.json({error:'Cancellation failed.'},{status:500});
  if (booking.calendar_event_id) await admin.from('calendar_events').update({ deleted_at: new Date().toISOString() }).eq('id', booking.calendar_event_id).eq('user_id',booking.assigned_user_id).eq('workspace_id',booking.workspace_id);
  await admin.from('sales_booking_reminders').delete().eq('booking_id', booking.id).eq('workspace_id',booking.workspace_id);
  return NextResponse.json({ cancelled: true });
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params; const { admin, booking } = await bookingFor(token); const body = await request.json().catch(() => ({})); const start = new Date(typeof body.startAt === 'string' ? body.startAt : '');
  if (!booking || Number.isNaN(start.getTime()) || start.getTime() < Date.now()) return NextResponse.json({ error: 'Booking or new time is invalid.' }, { status: 400 });
  const { data: oldEvent, error: eventError } = await admin.from('calendar_events').select('conference_id,title').eq('id',booking.calendar_event_id).eq('user_id',booking.assigned_user_id).eq('workspace_id',booking.workspace_id).maybeSingle();
  if (eventError) return NextResponse.json({error:'Calendar lookup failed.'},{status:500});
  if (!oldEvent) return NextResponse.json({error:'Booking calendar is unavailable.'},{status:409});
  const duration = Math.round((Date.parse(booking.ends_at) - Date.parse(booking.starts_at)) / 60_000); const end = new Date(start.getTime() + duration * 60_000);
  const [{ count: calendarConflict }, { count: bookingConflict }] = await Promise.all([
    admin.from('calendar_events').select('*', { count: 'exact', head: true }).eq('user_id', booking.assigned_user_id).is('deleted_at', null).neq('id', booking.calendar_event_id).lt('start_at', end.toISOString()).gt('end_at', start.toISOString()),
    admin.from('sales_bookings').select('*', { count: 'exact', head: true }).eq('assigned_user_id', booking.assigned_user_id).eq('status', 'confirmed').neq('id', booking.id).lt('starts_at', end.toISOString()).gt('ends_at', start.toISOString()),
  ]);
  if ((calendarConflict ?? 0) || (bookingConflict ?? 0)) return NextResponse.json({ error: 'That time is no longer available.' }, { status: 409 });
  const accessToken = await zoomAccessTokenForUser(admin, booking.assigned_user_id).catch(() => null);
  if (!accessToken) return NextResponse.json({ error: 'Host Zoom connection is unavailable.' }, { status: 409 });
  const zoom = await createZoomMeeting(accessToken, { topic: oldEvent?.title ?? booking.sales_booking_links?.title ?? 'WolfGrid meeting', startAt: start.toISOString(), durationMinutes: duration });
  if (oldEvent?.conference_id) await deleteZoomMeeting(accessToken, oldEvent.conference_id).catch(() => undefined);
  await admin.from('calendar_events').update({ start_at: start.toISOString(), end_at: end.toISOString(), conference_id: String(zoom.id), conference_join_url: zoom.join_url }).eq('id', booking.calendar_event_id).eq('user_id',booking.assigned_user_id).eq('workspace_id',booking.workspace_id);
  await admin.from('sales_bookings').update({ starts_at: start.toISOString(), ends_at: end.toISOString(), status: 'confirmed', outcome: 'rescheduled', zoom_join_url: zoom.join_url }).eq('id', booking.id);
  await admin.from('sales_booking_reminders').delete().eq('booking_id', booking.id).eq('workspace_id',booking.workspace_id);
  const reminderMinutes = booking.sales_booking_links?.reminder_minutes ?? [1440, 60]; const reminders = reminderMinutes.flatMap((minutes: number) => ['email', 'push'].map((channel) => ({ workspace_id: booking.workspace_id, booking_id: booking.id, channel, scheduled_for: new Date(start.getTime() - minutes * 60_000).toISOString() }))).filter((row: { scheduled_for: string }) => Date.parse(row.scheduled_for) > Date.now());
  if (reminders.length) await admin.from('sales_booking_reminders').insert(reminders);
  return NextResponse.json({ rescheduled: true, startsAt: start.toISOString(), joinUrl: zoom.join_url });
}
