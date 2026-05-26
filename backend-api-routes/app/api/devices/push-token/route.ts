import { NextRequest, NextResponse } from 'next/server';
import { resolveUserFromRequest } from '@/app/api/_utils/request-user';
import { createAdminClient } from '@/lib/supabase/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type PushTokenBody = {
  token?: string;
  platform?: string;
  environment?: string;
};

export async function POST(request: NextRequest) {
  const user = await resolveUserFromRequest(request);
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as PushTokenBody;
  const token = body.token?.trim();
  const platform = body.platform?.trim().toLowerCase() || 'ios';
  const environment = body.environment?.trim().toLowerCase() || 'production';

  if (!token) {
    return NextResponse.json({ error: 'Device token required' }, { status: 400 });
  }

  if (platform !== 'ios') {
    return NextResponse.json({ error: 'Unsupported platform' }, { status: 400 });
  }

  if (environment !== 'sandbox' && environment !== 'production') {
    return NextResponse.json({ error: 'Unsupported APNs environment' }, { status: 400 });
  }

  const now = new Date().toISOString();
  const supabase = createAdminClient();
  const { error } = await supabase
    .from('user_push_tokens')
    .upsert(
      {
        user_id: user.id,
        token,
        platform,
        environment,
        enabled: true,
        last_seen_at: now,
        updated_at: now,
      },
      { onConflict: 'user_id,token' }
    );

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
