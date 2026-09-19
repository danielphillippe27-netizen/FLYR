import { NextRequest, NextResponse } from 'next/server';
import { cleanText, requireSalesProContext } from '@/lib/sales-pro/context';
import { encryptICloudPassword, iCloudConnection, verifyICloudCredentials } from '@/lib/email/icloud-client';

export const runtime = 'nodejs';
export const maxDuration = 30;

function publicConnection(row: Awaited<ReturnType<typeof iCloudConnection>>) {
  return row ? {
    emailAddress: row.email_address,
    isActive: row.is_active,
    lastSyncedAt: row.last_synced_at,
  } : null;
}

export async function GET(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  try {
    return NextResponse.json({ connection: publicConnection(await iCloudConnection(context.admin, context.workspaceId, context.userId)) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Unable to load email connection.' }, { status: 500 });
  }
}

export async function PUT(request: NextRequest) {
  const context = await requireSalesProContext(request);
  if (context instanceof NextResponse) return context;
  const body = await request.json().catch(() => ({}));
  const emailAddress = cleanText(body.emailAddress)?.toLowerCase();
  const requestedAuthenticationEmailAddress = cleanText(body.authenticationEmailAddress)?.toLowerCase();
  const authenticationEmailAddress = requestedAuthenticationEmailAddress
    ?? (emailAddress === 'daniel@wolfgrid.app' ? 'daniel_phillippe@icloud.com' : undefined);
  const password = cleanText(body.appSpecificPassword)?.replace(/\s+/g, '');
  const isActive = body.isActive !== false;
  if (!emailAddress || !/^\S+@\S+\.\S+$/.test(emailAddress)) return NextResponse.json({ error: 'Enter your iCloud-hosted email address.' }, { status: 400 });
  if (!authenticationEmailAddress || !/^\S+@icloud\.com$/.test(authenticationEmailAddress)) {
    return NextResponse.json({ error: 'Enter the primary iCloud Mail address used to authenticate this mailbox.' }, { status: 400 });
  }
  let stage = 'load_connection';
  try {
    const existing = await iCloudConnection(context.admin, context.workspaceId, context.userId);
    if (isActive && !password && !existing?.app_password_encrypted) {
      return NextResponse.json({ error: 'Enter an Apple app-specific password.' }, { status: 400 });
    }
    const encryptedPassword = password ? encryptICloudPassword(password) : existing!.app_password_encrypted;
    if (isActive && password) {
      stage = 'verify_apple_connection';
      await verifyICloudCredentials(emailAddress, authenticationEmailAddress, password);
    }
    stage = 'save_connection';
    const { data, error } = await context.admin.from('email_connections').upsert({
      workspace_id: context.workspaceId, user_id: context.userId, provider: 'icloud',
      email_address: emailAddress, app_password_encrypted: encryptedPassword, is_active: isActive,
      sync_error: null, updated_at: new Date().toISOString(),
    }, { onConflict: 'workspace_id,user_id,provider' }).select('*').single();
    if (error) throw error;
    console.info('[api/email/apple/connection] connected', {
      stage: 'complete',
      mailboxDomain: emailAddress.split('@')[1],
      authenticationDomain: authenticationEmailAddress.split('@')[1],
    });
    return NextResponse.json({ connection: publicConnection(data) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to connect iCloud Mail.';
    const details = error && typeof error === 'object' ? error as Record<string, unknown> : {};
    console.error('[api/email/apple/connection] failed', {
      stage,
      name: error instanceof Error ? error.name : typeof error,
      message,
      code: details.code,
      responseStatus: details.responseStatus,
      responseText: details.responseText,
      serverResponseCode: details.serverResponseCode,
      command: details.command,
    });
    const appleRejectedLogin = /auth|login|credential|password|command failed/i.test(message);
    return NextResponse.json({
      error: appleRejectedLogin
        ? 'Apple rejected the connection. Paste the complete app-specific password, including its hyphens, and try again.'
        : message,
    }, { status: 409 });
  }
}
