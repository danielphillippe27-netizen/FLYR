import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const { data, error } = await context.admin.from('sales_mailboxes').select('*').eq('workspace_id', context.workspaceId).eq('user_id', context.userId).maybeSingle();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ mailbox: data });
}

export async function PUT(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const localPart = cleanText(body.localPart)?.toLowerCase().replace(/[^a-z0-9._-]/g, '').slice(0, 64);
  if (!localPart || localPart.length < 3) return NextResponse.json({ error: 'Choose a mailbox name with at least three characters.' }, { status: 400 });
  const forwardTo = cleanText(body.forwardTo)?.toLowerCase();
  if (forwardTo && !/^\S+@\S+\.\S+$/.test(forwardTo)) return NextResponse.json({ error: 'Forwarding address is invalid.' }, { status: 400 });
  const { data, error } = await context.admin.from('sales_mailboxes').upsert({ workspace_id: context.workspaceId, user_id: context.userId, local_part: localPart, forward_to: forwardTo, is_active: body.isActive !== false }, { onConflict: 'workspace_id,user_id' }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  return NextResponse.json({ mailbox: data });
}
