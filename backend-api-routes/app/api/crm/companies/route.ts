import { NextRequest, NextResponse } from 'next/server';
import { clampLimit, cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  let query = context.admin
    .from('sales_companies')
    .select('*,sales_contacts(id,name,email,phone),sales_leads(id,name,pipeline_stage_id,next_follow_up_at)')
    .eq('workspace_id', context.workspaceId).eq('owner_user_id', context.userId)
    .eq('sales_contacts.owner_user_id', context.userId).eq('sales_contacts.workspace_id', context.workspaceId)
    .eq('sales_leads.assigned_user_id', context.userId).eq('sales_leads.workspace_id', context.workspaceId)
    .is('merged_into_id', null)
    .order('updated_at', { ascending: false })
    .limit(clampLimit(request.nextUrl.searchParams.get('limit')));
  const domain = cleanText(request.nextUrl.searchParams.get('domain'))?.toLowerCase().replace(/^www\./, '');
  if (domain) query = query.eq('website_domain', domain);
  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ companies: data ?? [] });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const name = cleanText(body.name);
  if (!name) return NextResponse.json({ error: 'Company name is required.' }, { status: 400 });
  const { data, error } = await context.admin.from('sales_companies').insert({
    workspace_id: context.workspaceId,
    owner_user_id: context.userId,
    name,
    website: cleanText(body.website),
    website_domain: cleanText(body.websiteDomain)?.toLowerCase(),
    phone: cleanText(body.phone), email: cleanText(body.email)?.toLowerCase(), address: cleanText(body.address),
    city: cleanText(body.city), region: cleanText(body.region), country_code: cleanText(body.countryCode)?.toUpperCase(),
    notes: cleanText(body.notes), metadata: typeof body.metadata === 'object' && body.metadata ? body.metadata : {},
  }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  return NextResponse.json({ company: data }, { status: 201 });
}
