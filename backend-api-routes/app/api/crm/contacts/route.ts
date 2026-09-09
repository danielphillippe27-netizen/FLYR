import { requirePersonalReferences } from '@/lib/sales-pro/personal-references';
import { NextRequest, NextResponse } from 'next/server';
import { clampLimit, cleanText, normalizeEmail, normalizePhone, requireSalesProContext } from '@/lib/sales-pro/context';

export const dynamic = 'force-dynamic';

const SELECT = '*,sales_companies(id,name,website_domain),sales_leads(id,pipeline_stage_id,next_task_title,next_follow_up_at,last_touch_at)';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const limit = clampLimit(request.nextUrl.searchParams.get('limit'));
  const query = cleanText(request.nextUrl.searchParams.get('query'));
  let builder = context.admin
    .from('sales_contacts')
    .select(SELECT)
    .eq('sales_leads.assigned_user_id', context.userId).eq('sales_leads.workspace_id', context.workspaceId)
    .eq('sales_companies.owner_user_id', context.userId).eq('sales_companies.workspace_id', context.workspaceId)
    .eq('workspace_id', context.workspaceId).eq('owner_user_id', context.userId)
    .is('merged_into_id', null)
    .order('updated_at', { ascending: false })
    .limit(limit);
  if (query) builder = builder.or(`name.ilike.%${query}%,email.ilike.%${query}%,phone.ilike.%${query}%,company.ilike.%${query}%`);
  const { data, error } = await builder;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ contacts: data ?? [] });
}

export async function POST(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, { companyId: cleanText(body.companyId) }); }
  catch { return NextResponse.json({ error: 'Company not found.' }, { status: 404 }); }
  const name = cleanText(body.name);
  if (!name) return NextResponse.json({ error: 'Contact name is required.' }, { status: 400 });
  const email = normalizeEmail(body.email);
  const phone = normalizePhone(body.phone);
  if (email || phone) {
    const clauses = [email ? `email_normalized.eq.${email}` : null, phone ? `phone_e164.eq.${phone}` : null].filter(Boolean);
    const { data: duplicate } = await context.admin
      .from('sales_contacts')
      .select('id,name,email,phone')
      .eq('workspace_id', context.workspaceId).eq('owner_user_id', context.userId)
      .or(clauses.join(','))
      .is('merged_into_id', null)
      .limit(1)
      .maybeSingle();
    if (duplicate) return NextResponse.json({ error: 'A matching contact already exists.', duplicate }, { status: 409 });
  }
  const { data, error } = await context.admin
    .from('sales_contacts')
    .insert({
      workspace_id: context.workspaceId,
      owner_user_id: context.userId,
      company_id: cleanText(body.companyId),
      name,
      company: cleanText(body.company),
      phone: cleanText(body.phone),
      phone_e164: phone,
      email,
      email_normalized: email,
      website: cleanText(body.website),
      website_domain: cleanText(body.websiteDomain)?.toLowerCase(),
      address: cleanText(body.address),
      city: cleanText(body.city),
      region: cleanText(body.region),
      country_code: cleanText(body.countryCode)?.toUpperCase(),
      source: cleanText(body.source) ?? 'manual',
      metadata: typeof body.metadata === 'object' && body.metadata ? body.metadata : {},
    })
    .select('*')
    .single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ contact: data }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  try { await requirePersonalReferences(context.admin, context.workspaceId, context.userId, { companyId: cleanText(body.companyId) }); }
  catch { return NextResponse.json({ error: 'Company not found.' }, { status: 404 }); }
  const id = cleanText(body.id);
  if (!id) return NextResponse.json({ error: 'Contact id is required.' }, { status: 400 });
  const allowed: Record<string, string> = {
    name: 'name', companyId: 'company_id', company: 'company', phone: 'phone', email: 'email', website: 'website',
    address: 'address', city: 'city', region: 'region', countryCode: 'country_code', nextActionAt: 'next_action_at',
  };
  const updates: Record<string, unknown> = {};
  for (const [input, column] of Object.entries(allowed)) if (input in body) updates[column] = cleanText(body[input]);
  if ('email' in body) updates.email_normalized = normalizeEmail(body.email);
  if ('phone' in body) updates.phone_e164 = normalizePhone(body.phone);
  const { data, error } = await context.admin
    .from('sales_contacts')
    .update(updates)
    .eq('workspace_id', context.workspaceId).eq('owner_user_id', context.userId)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ contact: data });
}
