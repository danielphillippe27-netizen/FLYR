import type { SupabaseClient } from '@supabase/supabase-js';

type DemoEvent = { session_id: string; event_type: string; watch_seconds?: number | null; max_watch_seconds?: number | null };
const eventFields = {
  page_view: 'pageViews', video_started: 'videoStarts', play_with_sound: 'playWithSound',
  progress_25: 'progress25', progress_50: 'progress50', progress_75: 'progress75',
  video_complete: 'completions', cta_shown: 'ctaShown', start_trial_click: 'startTrialClicks',
  founder_call_click: 'founderCallClicks', page_exit: 'exits',
} as const;

export function summarizeDemoEvents(events: DemoEvent[]) {
  const counts = { pageViews: 0, videoStarts: 0, playWithSound: 0, progress25: 0, progress50: 0,
    progress75: 0, completions: 0, ctaShown: 0, startTrialClicks: 0, founderCallClicks: 0, exits: 0 };
  const sessions = new Map<string, number>();
  for (const event of events) {
    const field = eventFields[event.event_type as keyof typeof eventFields];
    if (field) counts[field]++;
    const seconds = Math.max(0, ...[event.watch_seconds, event.max_watch_seconds].map(value => Number.isFinite(value) ? Number(value) : 0));
    sessions.set(event.session_id, Math.max(sessions.get(event.session_id) ?? 0, seconds));
  }
  const watchTimes = [...sessions.values()];
  return { sessions: sessions.size, ...counts,
    averageWatchSeconds: watchTimes.length ? watchTimes.reduce((sum, value) => sum + value, 0) / watchTimes.length : 0,
    maxWatchSeconds: watchTimes.reduce((max, value) => Math.max(max, value), 0) };
}

export async function loadPersonalDemoMetrics(admin: SupabaseClient, salespersonId: string | null, start: string, end: string) {
  if (!salespersonId) return { opens: 0, demoVideo: summarizeDemoEvents([]) };
  const events: DemoEvent[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await admin.from('salesperson_demo_video_events')
      .select('session_id,event_type,watch_seconds,max_watch_seconds').eq('salesperson_id', salespersonId)
      .gte('created_at', start).lt('created_at', end).order('id').range(offset, offset + 999);
    if (error) throw error;
    events.push(...(data ?? []));
    if ((data?.length ?? 0) < 1000) break;
  }
  const { count, error } = await admin.from('salesperson_click_events').select('id', {count:'exact',head:true})
    .eq('salesperson_id', salespersonId).gte('created_at', start).lt('created_at', end);
  if (error) throw error;
  return { opens: count ?? 0, demoVideo: summarizeDemoEvents(events) };
}
