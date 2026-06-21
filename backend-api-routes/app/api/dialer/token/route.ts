import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import {
  cleanTelnyxToken,
  decodeTelnyxJwt,
  TelnyxJwtPayload,
  telnyxIdentifierMisconfiguration,
  validateTelnyxAccessTokenPayload,
} from '@/lib/dialer/telnyx-token';
import { createAdminClient } from '@/lib/supabase/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function envValue(name: string): string | null {
  const value = process.env[name]?.trim();
  return value ? value : null;
}

function envList(name: string): string[] {
  return (process.env[name] ?? '')
    .split(/[\n,]/)
    .map((value) => value.trim())
    .filter(Boolean);
}

function normalizeEmail(email: string | null): string | null {
  return email?.trim().toLowerCase() || null;
}

function isAllowedForDialer(workspaceId: string, email: string | null): boolean {
  const allowedWorkspaces = new Set(envList('DIALER_ENABLED_WORKSPACE_IDS'));
  const allowedEmails = new Set(envList('DIALER_ENABLED_EMAILS').map((value) => value.toLowerCase()));

  if (allowedWorkspaces.size === 0 && allowedEmails.size === 0) {
    return true;
  }

  return allowedWorkspaces.has(workspaceId) || (email ? allowedEmails.has(email) : false);
}

async function userCanAccessWorkspace(userId: string, workspaceId: string): Promise<boolean> {
  const supabase = createAdminClient();

  const { data: ownedWorkspace, error: ownedError } = await supabase
    .from('workspaces')
    .select('id')
    .eq('id', workspaceId)
    .eq('owner_id', userId)
    .maybeSingle();

  if (ownedError) {
    throw ownedError;
  }

  if (ownedWorkspace?.id) return true;

  const { data: membership, error: membershipError } = await supabase
    .from('workspace_members')
    .select('workspace_id')
    .eq('workspace_id', workspaceId)
    .eq('user_id', userId)
    .maybeSingle();

  if (membershipError) {
    throw membershipError;
  }

  return !!membership?.workspace_id;
}

async function createTelnyxAccessToken(
  credentialId: string
): Promise<{ token: string; payload: TelnyxJwtPayload }> {
  const credentialMisconfiguration = telnyxIdentifierMisconfiguration(credentialId);
  if (credentialMisconfiguration) {
    throw new Error(`TELNYX_IOS_TELEPHONY_CREDENTIAL_ID ${credentialMisconfiguration}`);
  }

  const apiKey = envValue('TELNYX_API_KEY');
  if (!apiKey) {
    throw new Error('TELNYX_API_KEY is not configured.');
  }

  const response = await fetch(
    `https://api.telnyx.com/v2/telephony_credentials/${encodeURIComponent(credentialId)}/token`,
    {
      method: 'POST',
      headers: {
        Accept: 'text/plain',
        Authorization: `Bearer ${apiKey}`,
      },
    }
  );

  const body = await response.text();
  if (!response.ok) {
    console.error('[dialer/token] Telnyx token request failed:', response.status, body.slice(0, 500));
    throw new Error('Telnyx rejected the telephony credential token request.');
  }

  const token = cleanTelnyxToken(body);
  const payload = decodeTelnyxJwt(token);
  const validationError = validateTelnyxAccessTokenPayload(payload);
  if (validationError) {
    throw new Error(
      `Telnyx returned an invalid Voice SDK token (${validationError}). ` +
        'Verify TELNYX_IOS_TELEPHONY_CREDENTIAL_ID is a Telnyx telephony credential ID.'
    );
  }

  return { token, payload };
}

export async function GET(request: NextRequest) {
  try {
    const user = await resolveUserFromRequest(request);
    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const workspaceId = request.nextUrl.searchParams.get('workspaceId')?.trim();
    if (!workspaceId) {
      return NextResponse.json({ error: 'workspaceId is required.' }, { status: 400 });
    }

    const email = normalizeEmail(user.email);
    if (!isAllowedForDialer(workspaceId, email)) {
      return NextResponse.json({ error: 'Dialer is not enabled for this workspace.' }, { status: 403 });
    }

    const canAccessWorkspace = await userCanAccessWorkspace(user.id, workspaceId);
    if (!canAccessWorkspace) {
      return NextResponse.json({ error: 'You are not authorized for this workspace.' }, { status: 403 });
    }

    const credentialId =
      envValue('TELNYX_IOS_TELEPHONY_CREDENTIAL_ID') ??
      envValue('TELNYX_TELEPHONY_CREDENTIAL_ID');
    if (!credentialId) {
      return NextResponse.json(
        { error: 'Telnyx telephony credential is not configured.' },
        { status: 503 }
      );
    }

    const { token, payload } = await createTelnyxAccessToken(credentialId);
    const expiresAt = payload?.exp ? new Date(payload.exp * 1000).toISOString() : null;

    return NextResponse.json({
      provider: 'telnyx',
      sdkTarget: 'telnyx-ios',
      token,
      identity: payload?.sub ?? credentialId,
      expiresAt,
      incomingAllowed: false,
      voipPushConfigured: !!envValue('TELNYX_IOS_PUSH_CREDENTIAL_ID'),
      telnyxTelephonyCredentialId: credentialId,
      requiresTelnyxVoiceSdk: true,
      fromNumber: envValue('TELNYX_FROM_NUMBER'),
    });
  } catch (error) {
    console.error('[dialer/token]', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Unable to create Telnyx voice token.' },
      { status: 500 }
    );
  }
}
