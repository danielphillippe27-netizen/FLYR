import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({})); const survivorId = cleanText(body.survivorId); const mergedId = cleanText(body.mergedId);
  if (!survivorId || !mergedId) return NextResponse.json({ error: 'survivorId and mergedId are required.' }, { status: 400 });
  const company = body.entityType === 'company';
  const { data: owned, error: ownershipError } = await context.admin.from(company ? 'sales_companies' : 'sales_contacts')
    .select('id').eq('workspace_id', context.workspaceId).eq('owner_user_id', context.userId).in('id', [survivorId, mergedId]);
  if (ownershipError || owned?.length !== 2) return NextResponse.json({ error: 'Records not found.' }, { status: 404 });
  const { data, error } = company
    ? await context.admin.rpc('merge_sales_companies', { target_workspace_id: context.workspaceId, survivor_company_id: survivorId, merged_company_id: mergedId, actor_id: context.userId })
    : await context.admin.rpc('merge_sales_contacts', { target_workspace_id: context.workspaceId, survivor_contact_id: survivorId, merged_contact_id: mergedId, actor_id: context.userId });
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  return NextResponse.json(company ? { companyId: data } : { contactId: data });
}
