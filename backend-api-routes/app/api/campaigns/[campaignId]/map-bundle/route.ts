import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { ensureCampaignAccess } from '@/app/api/campaigns/_utils/access';
import { CampaignMapBundleService } from '@/lib/services/CampaignMapBundleService';

const SUPABASE_URL = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

export const dynamic = 'force-dynamic';
export const revalidate = 0;
export const maxDuration = 300;

type RouteContext = { params: Promise<{ campaignId: string }> };

const JSON_NO_STORE_HEADERS = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store, max-age=0',
};

type ServerTimingSpan = { name: string; durationMs: number };

function serverTimingValue(spans: ServerTimingSpan[]): string {
  return spans
    .map((span) => {
      const name = span.name.replace(/[^A-Za-z0-9_-]/g, '_');
      return `${name};dur=${Math.max(0, span.durationMs).toFixed(1)}`;
    })
    .join(', ');
}

function headersWithTiming(spans: ServerTimingSpan[]) {
  const headers: Record<string, string> = { ...JSON_NO_STORE_HEADERS };
  const timing = serverTimingValue(spans);
  if (timing) headers['Server-Timing'] = timing;
  return headers;
}

function getAuthToken(request: Request): string | null {
  const authHeader = request.headers.get('authorization');
  return authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
}

function createAnonClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function createAdminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function authenticate(request: Request, campaignId: string) {
  const token = getAuthToken(request);
  if (!token) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401, headers: JSON_NO_STORE_HEADERS }) };
  }

  const anon = createAnonClient();
  const {
    data: { user },
    error: userError,
  } = await anon.auth.getUser(token);

  if (userError || !user) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401, headers: JSON_NO_STORE_HEADERS }) };
  }

  const admin = createAdminClient();
  const allowed = await ensureCampaignAccess(admin, campaignId, user.id);
  if (!allowed) {
    return { error: NextResponse.json({ error: 'Forbidden' }, { status: 403, headers: JSON_NO_STORE_HEADERS }) };
  }

  return { admin };
}

export async function GET(request: Request, context: RouteContext): Promise<Response> {
  const startedAt = performance.now();
  const timings: ServerTimingSpan[] = [];
  const recordTiming = (name: string, durationMs: number) => {
    timings.push({ name, durationMs });
  };
  const finalizeHeaders = () => {
    if (!timings.some((span) => span.name === 'total')) {
      recordTiming('total', performance.now() - startedAt);
    }
    return headersWithTiming(timings);
  };

  try {
    const { campaignId } = await context.params;
    const auth = await authenticate(request, campaignId);
    if (auth.error) {
      return new Response(await auth.error.text(), {
        status: auth.error.status,
        headers: finalizeHeaders(),
      });
    }

    const requestUrl = new URL(request.url);
    const localSignature = requestUrl.searchParams.get('signature');
    const service = new CampaignMapBundleService(auth.admin, recordTiming);
    const result = await service.resolve(campaignId, localSignature);

    if (result.status === 'not_modified') {
      return new Response(null, {
        status: 304,
        headers: finalizeHeaders(),
      });
    }

    return NextResponse.json(result.bundle, {
      status: 200,
      headers: finalizeHeaders(),
    });
  } catch (error) {
    console.error('[map-bundle] GET failed:', error);
    return NextResponse.json(
      { error: 'Failed to resolve campaign map bundle' },
      { status: 500, headers: finalizeHeaders() }
    );
  }
}
