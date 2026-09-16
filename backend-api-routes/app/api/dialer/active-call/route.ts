import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { resolveWorkspaceMembershipForUser, type MinimalSupabaseClient } from '@/app/api/_utils/workspace';
import { createAdminClient } from '@/lib/supabase/server';
import { ACTIVE_CALL_LEASE_MS, activeCallSyncSchema } from '@/lib/dialer/active-call';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** Renew this device's call and return this user's calls on other devices. */
export async function PUT(request: NextRequest) {
  const parsed = activeCallSyncSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: 'Invalid active call.' }, { status: 400 });
  const { workspaceId: requestedWorkspaceId, deviceId, platform, call } = parsed.data;
  // Foundation's UUID.uuidString is uppercase; Postgres returns lowercase UUIDs.
  const workspaceId = requestedWorkspaceId.toLowerCase();
  const requestUser = await resolveUserFromRequest(request);
  if (!requestUser) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const admin = createAdminClient();
  const membership = await resolveWorkspaceMembershipForUser(admin as unknown as MinimalSupabaseClient, requestUser.id, workspaceId);
  if (membership.workspaceId !== workspaceId) {
    return NextResponse.json({ error: 'Workspace access required.' }, { status: 403 });
  }
  const scope = { workspace_id: workspaceId, user_id: requestUser.id };
  const now = new Date();

  const mutation = call
    ? await admin.from('dialer_active_devices').upsert({
        ...scope,
        device_id: deviceId,
        platform,
        call_snapshot: call,
        updated_at: now.toISOString(),
        expires_at: new Date(now.getTime() + ACTIVE_CALL_LEASE_MS).toISOString(),
      }, { onConflict: 'workspace_id,user_id,device_id' })
    : await admin.from('dialer_active_devices').delete().match({ ...scope, device_id: deviceId });
  if (mutation.error) {
    console.error('[dialer/active-call] sync failed', mutation.error.code);
    return NextResponse.json({ error: 'Call sync unavailable.' }, { status: 503 });
  }

  // Clean expired rows only within the caller's authorized scope.
  await admin.from('dialer_active_devices').delete().match(scope).lte('expires_at', now.toISOString());
  const { data, error } = await admin.from('dialer_active_devices')
    .select('device_id,platform,call_snapshot,expires_at')
    .match(scope)
    .neq('device_id', deviceId)
    .gt('expires_at', now.toISOString())
    .order('updated_at', { ascending: false });
  if (error) return NextResponse.json({ error: 'Call sync unavailable.' }, { status: 503 });
  return NextResponse.json({
    calls: (data ?? []).map(row => ({
      ...row.call_snapshot,
      deviceId: row.device_id,
      platform: row.platform,
      expiresAt: row.expires_at,
    })),
  }, { headers: { 'Cache-Control': 'private, no-store' } });
}
