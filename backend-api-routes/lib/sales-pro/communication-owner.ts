import type { SupabaseClient } from '@supabase/supabase-js';

// A contact/lead assignee is not the recipient of a call or text. Only a unique
// active number assignment establishes ownership; unknown/shared numbers fail closed.
export async function communicationNumberOwner(admin: SupabaseClient, number: string | null) {
  if (!number) return null;
  const { data: assignment, error } = await admin.from('salesperson_dialer_settings')
    .select('salesperson_id,workspace_id').eq('assigned_phone_number', number)
    .eq('number_status', 'active').maybeSingle();
  if (error) throw error;
  if (!assignment) return null;
  const { data: person, error: personError } = await admin.from('salespeople')
    .select('user_id').eq('id', assignment.salesperson_id)
    .eq('workspace_id', assignment.workspace_id).eq('status', 'active').maybeSingle();
  if (personError) throw personError;
  if (!person?.user_id) return null;
  return { workspaceId: assignment.workspace_id as string, userId: person.user_id as string };
}
