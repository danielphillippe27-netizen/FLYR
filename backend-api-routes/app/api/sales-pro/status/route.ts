import { NextRequest, NextResponse } from 'next/server';
import { requireSalesProContext } from '@/lib/sales-pro/context';

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const { data } = await context.admin.from('sales_pro_rollouts').select('*').eq('workspace_id', context.workspaceId).maybeSingle();
  return NextResponse.json({ rollout: data ?? { workspace_id: context.workspaceId, mode: 'shadow', dual_write_enabled: true, reads_enabled: false, writes_enabled: false } });
}

export async function PATCH(request: NextRequest) {
  const context = await requireSalesProContext(request, { admin: true });
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  if (!['off', 'shadow', 'canary', 'enabled'].includes(body.mode)) return NextResponse.json({ error: 'A valid rollout mode is required.' }, { status: 400 });
  const { data, error } = await context.admin.from('sales_pro_rollouts').upsert({ workspace_id: context.workspaceId, mode: body.mode, dual_write_enabled: body.dualWriteEnabled !== false, reads_enabled: body.readsEnabled === true, writes_enabled: body.writesEnabled === true, enabled_at: body.mode === 'enabled' ? new Date().toISOString() : null }, { onConflict: 'workspace_id' }).select('*').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ rollout: data });
}
