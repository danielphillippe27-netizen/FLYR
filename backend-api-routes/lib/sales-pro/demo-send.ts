import type { SupabaseClient } from '@supabase/supabase-js';
import { appendCommunication, type CommunicationInput } from '@/lib/sales-pro/communications';
import { containsDemoLink } from '@/lib/salesperson/outreach-metrics';

/** Bridge older send surfaces without treating legacy contact IDs as Sales CRM IDs. */
export async function recordLegacyDemoSend(
  admin: SupabaseClient,
  input: CommunicationInput & { legacyContactId?: string | null }
): Promise<string | null> {
  if (!containsDemoLink(input.body)) return null;
  try {
    let leadId = input.leadId;
    let contactId: string | null = null;
    if (input.legacyContactId && !leadId) {
      const { data: lead, error } = await admin.from('sales_leads').select('id,sales_contact_id')
        .eq('workspace_id', input.workspaceId).eq('assigned_user_id', input.actorUserId)
        .eq('legacy_contact_id', input.legacyContactId).order('id').limit(1).maybeSingle();
      if (error) throw error;
      leadId = lead?.id ?? null;
      contactId = lead?.sales_contact_id ?? null;
    }
    const sent = await appendCommunication(admin, { ...input, leadId, contactId });
    return sent.event?.metadata?.demoFollowUpTaskId ? 'Demo sent. Your reminder is in Follow Up → Demo.' : null;
  } catch (error) {
    console.error('[demo-send] accepted send could not be recorded', error);
    return 'Demo sent, but its follow-up could not be recorded. Check Inbox before retrying.';
  }
}
