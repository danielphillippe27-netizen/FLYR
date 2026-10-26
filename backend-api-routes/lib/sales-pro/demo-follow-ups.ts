export type DemoFollowUp = {
  id: string;
  title: string;
  due_at: string | null;
  status: 'open' | 'completed' | 'dismissed';
  sales_lead_id: string | null;
  sales_contact_id: string | null;
  metadata: {
    recipientName?: string;
    recipientEmail?: string | null;
    recipientPhone?: string | null;
    firstSentAt?: string;
    lastSentAt?: string;
    lastChannel?: string;
    sendCount?: number;
    lastBody?: string;
    lastSubject?: string;
    replyReceivedAt?: string;
    outcome?: string;
    threadId?: string;
  };
};

export type DemoDueFilter = 'today' | 'overdue' | 'upcoming' | 'all';

export function demoMatchesFilter(task: DemoFollowUp, filter: DemoDueFilter, now = new Date()): boolean {
  if (filter === 'all') return true;
  if (task.status !== 'open' || !task.due_at) return false;
  const start = new Date(now); start.setHours(0, 0, 0, 0);
  const tomorrow = new Date(start); tomorrow.setDate(tomorrow.getDate() + 1);
  const due = Date.parse(task.due_at);
  if (filter === 'overdue') return due < start.getTime();
  if (filter === 'today') return due >= start.getTime() && due < tomorrow.getTime();
  return due >= tomorrow.getTime();
}
