import type { createAdminClient } from '@/lib/supabase/server';

type AdminClient = ReturnType<typeof createAdminClient>;

export type ResolvedCampaignBuilding = {
  rowId: string | null;
  publicId: string;
  persistence: 'silver' | 'snapshot';
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

/** Decode dynamic route params; rejoin segments when Overture ids were split on `/`. */
export function normalizeBuildingRouteId(input: string | string[]): string {
  if (Array.isArray(input)) {
    if (
      input.length >= 3 &&
      input[0]?.toLowerCase() === 'overture' &&
      input[1]?.toLowerCase() === 'building'
    ) {
      return `overture:building:${input.slice(2).map((part) => decodeURIComponent(part)).join(':')}`;
    }
    return input.map((part) => decodeURIComponent(part)).join('/');
  }

  const trimmed = input.trim();
  if (!trimmed) return trimmed;
  try {
    return decodeURIComponent(trimmed);
  } catch {
    return trimmed;
  }
}

export function buildingIdentifierCandidates(buildingIdParam: string): string[] {
  const trimmed = buildingIdParam.trim();
  if (!trimmed) return [];

  const candidates = [trimmed];
  const embedded = trimmed.match(
    /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i
  );
  if (embedded && embedded[0].toLowerCase() !== trimmed.toLowerCase()) {
    candidates.push(embedded[0]);
  }

  return [...new Set(candidates)];
}

export function isDiamondOrBedrockBuildingIdentifier(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;
  const lower = trimmed.toLowerCase();
  return (
    lower.startsWith('diamond:') ||
    /^bedrock_[a-z]+:/.test(lower) ||
    /^[a-z0-9_]+_buildings:/.test(lower) ||
    /^[a-z]{2}(?:-[a-z0-9]+)*-[a-z0-9-]*building-[a-z0-9-]+$/.test(lower)
  );
}

export async function resolveCampaignBuilding(
  supabase: AdminClient,
  campaignId: string,
  buildingIdParam: string | string[]
): Promise<ResolvedCampaignBuilding | null> {
  const normalizedParam = normalizeBuildingRouteId(buildingIdParam);
  const candidates = buildingIdentifierCandidates(normalizedParam);
  if (candidates.length === 0) return null;

  for (const candidate of candidates) {
    const buildingQuery = supabase
      .from('buildings')
      .select('id, gers_id')
      .eq('campaign_id', campaignId)
      .limit(1);

    const { data: row, error } = isUuid(candidate)
      ? await buildingQuery.or(`id.eq.${candidate},gers_id.eq.${candidate}`).maybeSingle()
      : await buildingQuery.eq('gers_id', candidate).maybeSingle();

    if (!error && row) {
      return {
        rowId: row.id,
        publicId: row.gers_id ?? row.id,
        persistence: 'silver',
      };
    }
  }

  const primary = candidates[0];
  if (isUuid(primary) || isDiamondOrBedrockBuildingIdentifier(primary)) {
    return { rowId: null, publicId: primary, persistence: 'snapshot' };
  }

  return null;
}
