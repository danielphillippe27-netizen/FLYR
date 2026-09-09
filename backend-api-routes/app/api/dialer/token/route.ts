import { NextRequest, NextResponse } from 'next/server';
import {
  cleanTelnyxToken,
  decodeTelnyxJwt,
  TelnyxJwtPayload,
  telnyxIdentifierMisconfiguration,
  validateTelnyxAccessTokenPayload,
} from '@/lib/dialer/telnyx-token';
import { getDialerRequestContext } from '@/lib/dialer/server';
import { getSalespersonDialerSettings } from '@/lib/dialer/salesperson-settings';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function envValue(name: string): string | null {
  const value = process.env[name]?.trim();
  return value ? value : null;
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
    const requestedWorkspaceId = request.nextUrl.searchParams.get('workspaceId')?.trim();
    if (!requestedWorkspaceId) {
      return NextResponse.json({ error: 'workspaceId is required.' }, { status: 400 });
    }
    // Use the same access rules as every other dialler endpoint. In particular,
    // active salesperson accounts receive the salesperson override instead of
    // being rejected by the legacy environment-only iOS token allowlist.
    const context = await getDialerRequestContext(request, requestedWorkspaceId);
    if (context instanceof NextResponse) return context;

    const assignment = await getSalespersonDialerSettings(context.admin, context.salesperson?.id);
    const voice = assignment?.number_status === 'active' && assignment.workspace_id === context.workspaceId
      ? assignment.provisioning_metadata
      : null;
    const assignedCredentialId = typeof voice?.telnyx_telephony_credential_id === 'string'
      ? voice.telnyx_telephony_credential_id.trim() : null;
    // A shared SDK credential can deliver another user's incoming calls even
    // when the response says incomingAllowed=false. Never issue one to a user.
    const credentialId = assignedCredentialId;
    if (!credentialId) {
      return NextResponse.json(
        { error: 'A personal phone number and voice credential must be assigned before calling.' },
        { status: 409 }
      );
    }

    const { token, payload } = await createTelnyxAccessToken(credentialId);
    const expiresAt = payload?.exp ? new Date(payload.exp * 1000).toISOString() : null;
    const fromNumber = context.settings.defaultFromNumber;
    const smsFromNumber = context.settings.defaultSmsFromNumber;

    return NextResponse.json({
      provider: 'telnyx',
      sdkTarget: 'telnyx-ios',
      token,
      identity: payload?.sub ?? credentialId,
      expiresAt,
      incomingAllowed: Boolean(assignedCredentialId && voice?.telnyx_inbound_configured === true),
      voipPushConfigured: assignedCredentialId
        ? voice?.telnyx_ios_push_configured === true
        : !!envValue('TELNYX_IOS_PUSH_CREDENTIAL_ID'),
      telnyxTelephonyCredentialId: credentialId,
      requiresTelnyxVoiceSdk: true,
      fromNumber,
      smsFromNumber,
      allowSmsFollowup: context.settings.allowSmsFollowup && !!smsFromNumber,
    });
  } catch (error) {
    console.error('[dialer/token]', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Unable to create Telnyx voice token.' },
      { status: 500 }
    );
  }
}
