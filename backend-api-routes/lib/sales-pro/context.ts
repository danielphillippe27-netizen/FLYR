import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { resolveWorkspaceMembershipForUser, type MinimalSupabaseClient, type WorkspaceRole } from '@/app/api/_utils/workspace';
import { createAdminClient } from '@/lib/supabase/server';

export type SalesProContext = {
  admin: ReturnType<typeof createAdminClient>;
  userId: string;
  email: string | null;
  workspaceId: string;
  role: WorkspaceRole;
};

export async function requireSalesProContext(
  request: NextRequest,
  options: { admin?: boolean } = {}
): Promise<SalesProContext | NextResponse> {
  const user = await resolveUserFromRequest(request);
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const admin = createAdminClient();
  const requestedWorkspaceId = request.nextUrl.searchParams.get('workspaceId');
  const membership = await resolveWorkspaceMembershipForUser(
    admin as unknown as MinimalSupabaseClient,
    user.id,
    requestedWorkspaceId
  );
  if (!membership.workspaceId || !membership.role) {
    return NextResponse.json({ error: membership.error ?? 'Workspace access is required.' }, { status: membership.status ?? 403 });
  }
  if (options.admin && membership.role !== 'owner' && membership.role !== 'admin') {
    return NextResponse.json({ error: 'Workspace admin access is required.' }, { status: 403 });
  }
  if (process.env.SALES_PRO_ENFORCE_ROLLOUT === 'true' && !request.nextUrl.pathname.startsWith('/api/sales-pro/')) {
    const { data: rollout } = await admin.from('sales_pro_rollouts').select('reads_enabled,writes_enabled').eq('workspace_id', membership.workspaceId).maybeSingle();
    const allowed = request.method === 'GET' ? rollout?.reads_enabled : rollout?.writes_enabled;
    if (!allowed) return NextResponse.json({ error: 'Sales Pro is not enabled for this workspace yet.', code: 'sales_pro_rollout_disabled' }, { status: 409 });
  }
  return {
    admin,
    userId: user.id,
    email: user.email ?? null,
    workspaceId: membership.workspaceId,
    role: membership.role,
  };
}

export function cleanText(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function clampLimit(value: string | null, fallback = 50, maximum = 200): number {
  const parsed = Number(value ?? fallback);
  return Number.isFinite(parsed) ? Math.min(Math.max(Math.trunc(parsed), 1), maximum) : fallback;
}

export function encodeCursor(date: string, id: string): string {
  return Buffer.from(JSON.stringify({ date, id }), 'utf8').toString('base64url');
}

export function decodeCursor(value: string | null): { date: string; id: string } | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as { date?: unknown; id?: unknown };
    if (typeof parsed.date !== 'string' || typeof parsed.id !== 'string') return null;
    if (Number.isNaN(Date.parse(parsed.date))) return null;
    return { date: parsed.date, id: parsed.id };
  } catch {
    return null;
  }
}

export function normalizeEmail(value: unknown): string | null {
  return cleanText(value)?.toLowerCase() ?? null;
}

export function normalizePhone(value: unknown): string | null {
  const text = cleanText(value);
  if (!text) return null;
  const digits = text.replace(/\D/g, '');
  if (digits.length < 7) return null;
  return `+${digits}`;
}
