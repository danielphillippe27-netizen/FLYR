import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';
import { ensureSalespersonLeadMaster } from '@/lib/sales-leads/master-list';

export async function POST(request: NextRequest, { params }: { params: Promise<{ contactId: string }> }) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const salesWorkspaceId = context.salesperson?.workspace_id || context.access.workspaceId;
  if (!salesWorkspaceId) return NextResponse.json({ error: 'Create lead is available from the WolfGrid Sales workspace.' }, { status: 403 });
  const { contactId } = await params;
  const { data: contact } = await context.admin.from('social_contacts').select('*').eq('id', contactId).eq('social_workspace_id', context.socialWorkspaceId).single();
  if (!contact) return NextResponse.json({ error: 'Social contact not found' }, { status: 404 });
  if (contact.sales_lead_id) return NextResponse.json({ leadId: contact.sales_lead_id, existing: true });
  const result = await ensureSalespersonLeadMaster(context.admin, {
    workspaceId: salesWorkspaceId,
    assignedUserId: context.user.id,
    assignedSalespersonId: context.salesperson?.id || null,
    createdByUserId: context.user.id,
    name: contact.display_name || contact.username || 'Social contact',
    phone: contact.phone,
    email: contact.email,
    source: `social_${contact.platform}`,
    externalId: contact.external_id,
    state: 'assigned',
    notes: `Created manually from WolfSocial (${contact.platform}).`,
    metadata: { socialContactId: contact.id, socialWorkspaceId: context.socialWorkspaceId, username: contact.username },
  });
  if (!result.row?.id) return NextResponse.json({ error: result.warning || 'Could not create lead' }, { status: 500 });
  await context.admin.from('social_contacts').update({ sales_lead_id: result.row.id, updated_at: new Date().toISOString() }).eq('id', contact.id);
  return NextResponse.json({ leadId: result.row.id, created: result.created, existing: result.existing }, { status: result.created ? 201 : 200 });
}

