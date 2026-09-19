import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { verifyTelnyxWebhookSignature } from '@/lib/dialer/telnyx-messaging';
import { normalizePhoneNumber } from '@/lib/dialer/phone';
import { answerTelnyxCall, getTelnyxTelephonyCredential, transferTelnyxCall } from '@/lib/dialer/telnyx';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Dedicated number applications send calls here. Resolve the recipient only
// from the active number assignment, never from the shared default identity.
export async function POST(request: NextRequest) {
  const rawBody = await request.text();
  if (!verifyTelnyxWebhookSignature({
    rawBody,
    signature: request.headers.get('telnyx-signature-ed25519'),
    timestamp: request.headers.get('telnyx-timestamp'),
    publicKey: process.env.TELNYX_PUBLIC_KEY,
  })) return NextResponse.json({ error: 'Invalid Telnyx webhook signature.' }, { status: 403 });

  try {
    const event = JSON.parse(rawBody);
    const payload = event.data?.payload;
    if (event.data?.event_type !== 'call.initiated' || payload?.direction !== 'incoming') {
      return NextResponse.json({ ok: true, ignored: true });
    }
    const calledNumber = normalizePhoneNumber(typeof payload.to === 'string' ? payload.to : null).e164;
    const callId = typeof payload.call_control_id === 'string' ? payload.call_control_id : null;
    if (!calledNumber || !callId) return NextResponse.json({ error: 'Missing call destination.' }, { status: 400 });

    const admin = createAdminClient();
    const { data: assignment, error } = await admin.from('salesperson_dialer_settings')
      .select('salesperson_id, workspace_id, provisioning_metadata')
      .eq('assigned_phone_number', calledNumber).eq('number_status', 'active').maybeSingle();
    if (error) throw error;
    const voice = assignment?.provisioning_metadata;
    const credentialId = typeof voice?.telnyx_telephony_credential_id === 'string'
      ? voice.telnyx_telephony_credential_id.trim() : null;
    if (!assignment || !credentialId || voice?.telnyx_inbound_configured !== true) {
      return NextResponse.json({ error: 'No active recipient for number.' }, { status: 404 });
    }
    if (payload.connection_id !== voice.telnyx_call_control_application_id) {
      return NextResponse.json({ error: 'Call application does not match number.' }, { status: 403 });
    }
    const { data: salesperson, error: salespersonError } = await admin.from('salespeople')
      .select('user_id').eq('id', assignment.salesperson_id)
      .eq('workspace_id', assignment.workspace_id).eq('status', 'active').maybeSingle();
    if (salespersonError) throw salespersonError;
    if (!salesperson?.user_id) return NextResponse.json({ error: 'Recipient is inactive.' }, { status: 404 });

    const credential = await getTelnyxTelephonyCredential(credentialId);
    if (!credential.sipUsername || !/^[a-zA-Z0-9_.-]+$/.test(credential.sipUsername)) {
      throw new Error('Recipient has no valid SIP destination.');
    }
    await answerTelnyxCall(callId, { commandId: `${callId}:assigned-answer` });
    await transferTelnyxCall(callId, {
      to: `sip:${credential.sipUsername}@sip.telnyx.com`,
      from: calledNumber,
      timeoutSecs: 45,
      commandId: `${callId}:assigned-transfer`,
    });
    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error('[telnyx/voice/incoming] Unable to route assigned call', error);
    return NextResponse.json({ error: 'Unable to route call.' }, { status: 500 });
  }
}
