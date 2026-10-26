export type LastContactedLead = {
  last_contacted_at?: string | null;
  last_touch_at?: string | null;
  last_attempted_at?: string | null;
  called_at?: string | null;
  latest_call_created_at?: string | null;
  shared_call_history?: { last_called_at: string; last_called_by: string } | null;
};

export function lastContactedAt(lead: LastContactedLead): Date | null {
  const dates = [lead.last_contacted_at, lead.last_touch_at, lead.last_attempted_at,
    lead.called_at, lead.latest_call_created_at, lead.shared_call_history?.last_called_at]
    .filter((value): value is string => Boolean(value))
    .map((value) => Date.parse(value)).filter(Number.isFinite);
  return dates.length ? new Date(Math.max(...dates)) : null;
}

export function lastContactedLabel(lead: LastContactedLead, now = new Date()): string {
  const date = lastContactedAt(lead);
  if (!date) return 'Never contacted';
  const dayKey = (value: Date) => `${value.getFullYear()}-${value.getMonth()}-${value.getDate()}`;
  if (dayKey(date) === dayKey(now)) return date.toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit' });
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (dayKey(date) === dayKey(yesterday)) return 'Yesterday';
  return date.toLocaleDateString('en-CA', { month: 'short', day: 'numeric', ...(date.getFullYear() !== now.getFullYear() ? { year: 'numeric' } : {}) });
}
