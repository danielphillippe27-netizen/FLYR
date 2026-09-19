import type { SupabaseClient } from '@supabase/supabase-js';
import { sendApnsNotification } from '@/lib/notifications/apns';

export async function notifySalesUser(admin: SupabaseClient, input: { workspaceId: string; userId?: string | null; type: string; title: string; body?: string | null; data?: Record<string, unknown> }) {
  if (!input.userId) return;
  await admin.from('sales_notifications').insert({ workspace_id: input.workspaceId, user_id: input.userId, type: input.type, title: input.title, body: input.body ?? null, data: input.data ?? {} });
  const { data: tokens } = await admin.from('user_push_tokens').select('token,environment').eq('user_id', input.userId).eq('platform', 'ios').eq('enabled', true);
  await Promise.allSettled((tokens ?? []).map((row) => sendApnsNotification({ token: row.token, environment: row.environment === 'sandbox' ? 'sandbox' : 'production', payload: { aps: { alert: { title: input.title, body: input.body ?? undefined }, sound: 'default', 'thread-id': `sales:${input.type}` }, type: input.type, ...input.data } })));
}
