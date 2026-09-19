import type { SupabaseClient } from '@supabase/supabase-js';

/** Social workspaces are separate from sales workspaces; attribution is the user. */
export async function countPersonalDirectMessages(admin: SupabaseClient, userId: string, start: string, end: string) {
  const base = (selection: string) => admin.from('social_interactions')
    .select(selection, { count: 'exact', head: true }).eq('user_id', userId)
    .eq('direction', 'outbound').gte('occurred_at', start).lt('occurred_at', end);
  const [messages, replies] = await Promise.all([
    base('id').eq('kind', 'message'),
    base('id,social_threads!inner(kind)').eq('kind', 'reply').eq('social_threads.kind', 'message'),
  ]);
  if (messages.error) throw messages.error;
  if (replies.error) throw replies.error;
  return { count: (messages.count ?? 0) + (replies.count ?? 0), error: null };
}
