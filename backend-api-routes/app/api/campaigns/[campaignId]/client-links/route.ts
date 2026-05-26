import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { ensureCampaignAccess } from '@/app/api/campaigns/_utils/access';

const SUPABASE_URL = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

export const dynamic = 'force-dynamic';
export const revalidate = 0;

type RouteContext = { params: Promise<{ campaignId: string }> };

type ClientGeneratedLinkPayload = {
  building_id?: unknown;
  address_id?: unknown;
  match_type?: unknown;
  confidence?: unknown;
  distance_meters?: unknown;
};

type CampaignAddressLinkRow = {
  id: string;
  building_gers_id: string | null;
  match_source: string | null;
  confidence: number | null;
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function getAuthToken(request: Request): string | null {
  const authHeader = request.headers.get('authorization');
  return authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
}

function normalizedString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function normalizedConfidence(value: unknown): number {
  const confidence = finiteNumber(value);
  if (confidence == null) return 0.5;
  return Math.max(0, Math.min(1, confidence));
}

function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

function isUuidColumnTextIdError(error: { code?: string; message?: string } | null): boolean {
  const message = error?.message?.toLowerCase() ?? '';
  return error?.code === '22P02' || (
    message.includes('invalid input syntax') &&
    message.includes('uuid')
  );
}

function normalizeLink(raw: ClientGeneratedLinkPayload) {
  const buildingId = normalizedString(raw.building_id);
  const addressId = normalizedString(raw.address_id);
  if (!buildingId || !addressId) return null;

  return {
    buildingId,
    addressId,
    matchType: normalizedString(raw.match_type) ?? 'client_auto',
    confidence: normalizedConfidence(raw.confidence),
    distanceMeters: finiteNumber(raw.distance_meters),
  };
}

async function authenticate(request: Request, campaignId: string) {
  const token = getAuthToken(request);
  if (!token) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  }

  const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  const {
    data: { user },
    error: userError,
  } = await supabaseAnon.auth.getUser(token);

  if (userError || !user) {
    return { error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) };
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  const allowed = await ensureCampaignAccess(supabase, campaignId, user.id);
  if (!allowed) {
    return { error: NextResponse.json({ error: 'Forbidden' }, { status: 403 }) };
  }

  return { supabase, user };
}

export async function GET(request: Request, context: RouteContext): Promise<Response> {
  try {
    const { campaignId } = await context.params;
    const auth = await authenticate(request, campaignId);
    if (auth.error) return auth.error;

    const { data, error } = await auth.supabase
      .from('campaign_addresses')
      .select('id, building_gers_id, match_source, confidence')
      .eq('campaign_id', campaignId)
      .eq('match_source', 'client_auto')
      .not('building_gers_id', 'is', null);

    if (error) {
      console.error('[client-links] GET failed:', error);
      return NextResponse.json({ error: 'Failed to read client generated links' }, { status: 500 });
    }

    const links = ((data ?? []) as CampaignAddressLinkRow[]).flatMap((row) => {
      const buildingId = normalizedString(row.building_gers_id);
      if (!buildingId) return [];
      return [{
        building_id: buildingId,
        address_id: row.id,
        match_type: row.match_source ?? 'client_auto',
        confidence: row.confidence ?? 0.5,
      }];
    });

    return NextResponse.json({ campaign_id: campaignId, links });
  } catch (error) {
    console.error('[client-links] GET error:', error);
    return NextResponse.json({ error: 'Failed to read client generated links' }, { status: 500 });
  }
}

export async function POST(request: Request, context: RouteContext): Promise<Response> {
  try {
    const { campaignId } = await context.params;
    const auth = await authenticate(request, campaignId);
    if (auth.error) return auth.error;

    const body = await request.json().catch(() => null);
    const rawLinks = Array.isArray((body as { links?: unknown } | null)?.links)
      ? ((body as { links: ClientGeneratedLinkPayload[] }).links ?? [])
      : [];
    const links = rawLinks
      .map(normalizeLink)
      .filter((link): link is NonNullable<ReturnType<typeof normalizeLink>> => link !== null);

    if (links.length === 0) {
      return NextResponse.json({ campaign_id: campaignId, saved: 0, skipped: 0 });
    }
    if (links.length > 25_000) {
      return NextResponse.json({ error: 'Too many links in one publish request' }, { status: 413 });
    }

    const addressIds = Array.from(new Set(links.map((link) => link.addressId)));
    const { data: addresses, error: addressError } = await auth.supabase
      .from('campaign_addresses')
      .select('id, match_source')
      .eq('campaign_id', campaignId)
      .in('id', addressIds);

    if (addressError) {
      console.error('[client-links] address lookup failed:', addressError);
      return NextResponse.json({ error: 'Failed to verify campaign addresses' }, { status: 500 });
    }

    const addressSourceById = new Map(
      ((addresses ?? []) as Array<{ id: string; match_source: string | null }>).map((row) => [
        row.id.toLowerCase(),
        row.match_source?.toLowerCase() ?? null,
      ])
    );
    const acceptedLinks = links.filter((link) => {
      const source = addressSourceById.get(link.addressId.toLowerCase());
      return source !== undefined && source !== 'manual';
    });

    let saved = 0;
    let skippedForUuidSchema = 0;
    let externalTextIdsUnsupported = false;
    for (const link of acceptedLinks) {
      if (externalTextIdsUnsupported && !isUuid(link.buildingId)) {
        skippedForUuidSchema += 1;
        continue;
      }

      const { error } = await auth.supabase
        .from('campaign_addresses')
        .update({
          building_gers_id: link.buildingId,
          match_source: 'client_auto',
          confidence: link.confidence,
        })
        .eq('campaign_id', campaignId)
        .eq('id', link.addressId)
        .or('match_source.is.null,match_source.neq.manual');

      if (error) {
        console.error('[client-links] address update failed:', {
          campaignId,
          addressId: link.addressId,
          error,
        });
        if (!isUuid(link.buildingId) && isUuidColumnTextIdError(error)) {
          externalTextIdsUnsupported = true;
          skippedForUuidSchema += 1;
          console.warn(
            '[client-links] campaign_addresses.building_gers_id rejected text ids; skipping client-generated external links until DB migration is applied'
          );
          continue;
        }
        return NextResponse.json({ error: 'Failed to save client generated links' }, { status: 500 });
      }
      saved += 1;
    }

    return NextResponse.json({
      campaign_id: campaignId,
      asset_signature: normalizedString((body as { asset_signature?: unknown } | null)?.asset_signature),
      saved,
      skipped: links.length - acceptedLinks.length + skippedForUuidSchema,
    });
  } catch (error) {
    console.error('[client-links] POST error:', error);
    return NextResponse.json({ error: 'Failed to save client generated links' }, { status: 500 });
  }
}
