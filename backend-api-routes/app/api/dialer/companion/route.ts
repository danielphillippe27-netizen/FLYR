import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';
import { normalizePhoneNumber } from '@/lib/dialer/phone';

// Always resolve contacts within the signed-in user's current workspace.
export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const phone = normalizePhoneNumber(request.nextUrl.searchParams.get('phone')).e164;
  const leadId = cleanText(request.nextUrl.searchParams.get('leadId'));
  if (!phone && !leadId) return NextResponse.json({ leads: [] });
  let query = context.admin.from('sales_leads')
    .select('id,name,company,phone,email,address,notes,updated_at,next_follow_up_at')
    .eq('workspace_id', context.workspaceId).eq('assigned_user_id', context.userId);
  query = leadId ? query.eq('id', leadId) : query.eq('phone_e164', phone!);
  const { data, error } = await query.order('updated_at', { ascending: false }).limit(20);
  if (error) return NextResponse.json({ error: 'Unable to load the call contact.' }, { status: 503 });
  return NextResponse.json({ leads: data ?? [] }, { headers: { 'Cache-Control': 'private, no-store' } });
}
