export type BusinessWindow = { timezone: string; weekdays: number[]; startMinute: number; endMinute: number };

export function localClock(at: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(at);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return { weekday: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(value.weekday), minute: Number(value.hour) * 60 + Number(value.minute) };
}

export function isInsideBusinessWindow(at: Date, window: BusinessWindow) {
  const clock = localClock(at, window.timezone);
  return window.weekdays.includes(clock.weekday) && clock.minute >= window.startMinute && clock.minute < window.endMinute;
}

export function legacyPipelineStageKey(value: string | null | undefined) {
  if (value === 'new_lead') return 'new';
  if (value === 'attempting_contact' || value === 'nurture') return 'contacted';
  if (value === 'connected') return 'conversation';
  if (['demo_sent', 'trial_sent', 'trial_active', 'closing'].includes(value ?? '')) return 'proposal';
  if (value === 'won' || value === 'lost') return value;
  return 'new';
}
