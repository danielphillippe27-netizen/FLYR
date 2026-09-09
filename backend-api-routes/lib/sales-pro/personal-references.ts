import type { createAdminClient } from '@/lib/supabase/server';

/** Service-role queries bypass RLS, so authorize every linked personal record. */
export async function requirePersonalReferences(
  admin: ReturnType<typeof createAdminClient>,
  workspaceId: string,
  userId: string,
  references: { contactId?: string | null; leadId?: string | null; companyId?: string | null }
) {
  for (const [table, owner, id] of [
    ['sales_contacts', 'owner_user_id', references.contactId],
    ['sales_companies', 'owner_user_id', references.companyId],
    ['sales_leads', 'assigned_user_id', references.leadId],
  ] as const) {
    if (!id) continue;
    const { data, error } = await admin.from(table).select('id')
      .eq('workspace_id', workspaceId).eq(owner, userId).eq('id', id).maybeSingle();
    if (error) throw error;
    if (!data) throw new Error('Linked record not found.');
  }
}
