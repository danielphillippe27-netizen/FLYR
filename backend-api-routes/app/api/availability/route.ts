import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const userId = cleanText(request.nextUrl.searchParams.get('userId')) ?? context.userId;
  const [{ data: rules, error }, { data: overrides }] = await Promise.all([
    context.admin.from('sales_availability_rules').select('*').eq('workspace_id', context.workspaceId).eq('user_id', userId).order('weekday').order('start_minute'),
    context.admin.from('sales_availability_overrides').select('*').eq('workspace_id', context.workspaceId).eq('user_id', userId).gte('ends_at', new Date().toISOString()).order('starts_at'),
  ]);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ rules: rules ?? [], overrides: overrides ?? [] });
}

export async function PUT(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const userId = context.role === 'owner' || context.role === 'admin' ? cleanText(body.userId) ?? context.userId : context.userId;
  const rules = Array.isArray(body.rules) ? body.rules : [];
  if (rules.some((rule) => !Number.isInteger(rule.weekday) || rule.weekday < 0 || rule.weekday > 6 || !Number.isInteger(rule.startMinute) || !Number.isInteger(rule.endMinute) || rule.startMinute >= rule.endMinute)) {
    return NextResponse.json({ error: 'Availability rules are invalid.' }, { status: 400 });
  }
  await context.admin.from('sales_availability_rules').delete().eq('workspace_id', context.workspaceId).eq('user_id', userId);
  const rows = rules.map((rule) => ({ workspace_id: context.workspaceId, user_id: userId, weekday: rule.weekday, start_minute: rule.startMinute, end_minute: rule.endMinute, timezone: cleanText(rule.timezone) ?? cleanText(body.timezone) ?? 'UTC', is_active: rule.isActive !== false }));
  const { data, error } = rows.length ? await context.admin.from('sales_availability_rules').insert(rows).select('*') : { data: [], error: null };
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ rules: data ?? [] });
}
