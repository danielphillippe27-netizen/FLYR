import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { ReverseGeocodeService } from "@/lib/services/ReverseGeocodeService";
import { StableLinkerService } from "@/lib/services/StableLinkerService";
import { fetchAllInPages } from "@/lib/supabase/fetchAllInPages";

function firstNonEmptyEnv(...keys: string[]): string | null {
  for (const key of keys) {
    const value = process.env[key]?.trim();
    if (value) return value;
  }
  return null;
}

const SUPABASE_URL = firstNonEmptyEnv("SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = firstNonEmptyEnv("SUPABASE_SERVICE_ROLE_KEY");
const SUPABASE_AUTH_KEY = firstNonEmptyEnv(
  "SUPABASE_ANON_KEY",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY"
);

type RouteContext = { params: Promise<{ campaignId: string; buildingId: string }> };
type Point = [number, number];

type BuildingGeometry = {
  type: "Polygon" | "MultiPolygon";
  coordinates: number[][][] | number[][][][];
};

type ResolvedBuilding = {
  rowId: string | null;
  publicId: string;
  geometry: BuildingGeometry;
  streetName: string | null;
};

type AddressRow = {
  id: string;
  formatted: string | null;
  house_number: string | null;
  street_name: string | null;
  source: string | null;
  geom: unknown;
  building_id?: string | null;
  building_gers_id?: string | null;
};

type LinkRow = {
  address_id: string;
  building_id: string | null;
  confidence: number | null;
  match_type: string | null;
};

type OrphanRow = {
  address_id: string;
  coordinate: unknown;
  status: string | null;
  nearest_building_id: string | null;
  nearest_distance: number | null;
  suggested_street: string | null;
  address_street: string | null;
};

type CachedBuildingFeature = {
  id?: unknown;
  type?: unknown;
  geometry?: unknown;
  properties?: Record<string, unknown>;
};

function getAuthToken(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

async function ensureCampaignAccess(supabase: any, campaignId: string, userId: string): Promise<boolean> {
  const { data: campaign, error: campError } = await supabase
    .from("campaigns")
    .select("id, owner_id, workspace_id")
    .eq("id", campaignId)
    .maybeSingle();
  if (campError || !campaign) return false;

  const row = campaign as { owner_id: string; workspace_id: string | null };
  if (row.owner_id === userId) return true;

  if (row.workspace_id) {
    const { data: member } = await supabase
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", row.workspace_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (member) return true;

    const { data: workspace } = await supabase
      .from("workspaces")
      .select("owner_id")
      .eq("id", row.workspace_id)
      .maybeSingle();
    if (workspace && (workspace as { owner_id: string }).owner_id === userId) return true;
  }

  const { data: campaignMember } = await supabase
    .from("campaign_members")
    .select("campaign_id")
    .eq("campaign_id", campaignId)
    .eq("user_id", userId)
    .maybeSingle();
  return Boolean(campaignMember);
}

function parseGeometry(value: unknown): BuildingGeometry | null {
  const raw = typeof value === "string" ? JSON.parse(value) : value;
  if (!raw || typeof raw !== "object") return null;
  const candidate = raw as { type?: unknown; coordinates?: unknown };
  if ((candidate.type === "Polygon" || candidate.type === "MultiPolygon") && Array.isArray(candidate.coordinates)) {
    return candidate as BuildingGeometry;
  }
  return null;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function finiteQueryNumber(url: URL, name: string): number | null {
  const value = Number(url.searchParams.get(name));
  return Number.isFinite(value) ? value : null;
}

function normalizedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizedIdentifierSet(...values: Array<string | null | undefined>): Set<string> {
  return new Set(
    values
      .map((value) => value?.trim().toLowerCase())
      .filter((value): value is string => Boolean(value))
  );
}

function buildingIdentifiersFromRequest(url: URL, buildingId: string): string[] {
  const repeated = url.searchParams.getAll("building_identifier");
  const commaSeparated = (url.searchParams.get("building_identifiers") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return Array.from(new Set([buildingId, ...repeated, ...commaSeparated].map((value) => value.trim()).filter(Boolean)));
}

function buildingIdentifierCandidates(feature: CachedBuildingFeature): string[] {
  const properties = feature.properties ?? {};
  const identifiers = [
    normalizedString(properties.building_id),
    normalizedString(properties.gers_id),
    normalizedString(properties.id),
    normalizedString(feature.id),
  ].filter((value): value is string => Boolean(value));

  return Array.from(new Set(identifiers));
}

async function resolveBuildingFromPolishedCache(
  supabase: any,
  campaignId: string,
  buildingIdParam: string
): Promise<ResolvedBuilding | null> {
  const normalizedParam = buildingIdParam.trim().toLowerCase();
  if (!normalizedParam) return null;

  const { data, error } = await supabase
    .from("campaign_polished_building_features")
    .select("feature_collection")
    .eq("campaign_id", campaignId)
    .maybeSingle();

  if (error || !data) return null;

  const featureCollection = (data as { feature_collection?: unknown }).feature_collection;
  const features = (featureCollection as { features?: unknown[] } | null)?.features;
  if (!Array.isArray(features)) return null;

  for (const rawFeature of features) {
    if (!rawFeature || typeof rawFeature !== "object") continue;
    const feature = rawFeature as CachedBuildingFeature;
    const identifiers = buildingIdentifierCandidates(feature);
    if (!identifiers.some((identifier) => identifier.toLowerCase() === normalizedParam)) continue;

    const geometry = parseGeometry(feature.geometry);
    if (!geometry) continue;

    const properties = feature.properties ?? {};
    return {
      rowId: null,
      publicId: identifiers[0] ?? buildingIdParam,
      geometry,
      streetName:
        normalizedString(properties.street_name) ??
        normalizedString(properties.primary_street_name),
    };
  }

  return null;
}

async function resolveBuilding(supabase: any, campaignId: string, buildingIdParam: string): Promise<ResolvedBuilding | null> {
  const buildingQuery = supabase
    .from("buildings")
    .select("id, gers_id, geom")
    .eq("campaign_id", campaignId)
    .limit(1);
  const buildingBuilder = isUuid(buildingIdParam)
    ? buildingQuery.or(`id.eq.${buildingIdParam},gers_id.eq.${buildingIdParam}`)
    : buildingQuery.eq("gers_id", buildingIdParam);
  const { data: buildingRow } = await buildingBuilder.maybeSingle();
  if (buildingRow) {
    const row = buildingRow as { id: string; gers_id: string | null; geom: unknown };
    const geometry = parseGeometry(row.geom);
    if (geometry) {
      return { rowId: row.id, publicId: row.gers_id ?? row.id, geometry, streetName: null };
    }
  }

  const cachedBuilding = await resolveBuildingFromPolishedCache(supabase, campaignId, buildingIdParam);
  if (cachedBuilding) return cachedBuilding;

  if (!isUuid(buildingIdParam)) return null;
  const { data: goldRow } = await supabase
    .from("ref_buildings_gold")
    .select("id, geom, primary_street_name")
    .eq("id", buildingIdParam)
    .maybeSingle();
  if (!goldRow) return null;
  const gold = goldRow as { id: string; geom: unknown; primary_street_name: string | null };
  const geometry = parseGeometry(gold.geom);
  return geometry ? { rowId: null, publicId: gold.id, geometry, streetName: gold.primary_street_name } : null;
}

async function reverseCandidatePayload(point: { lat: number; lng: number }): Promise<Record<string, unknown> | null> {
  const reverse = await ReverseGeocodeService.mapboxReverseAddress(point);
  if (!reverse) return null;
  const formatted = reverse.street_line ?? reverse.formatted_address;

  return {
    id: crypto.randomUUID(),
    candidate_type: "reverse_geocode",
    is_synthetic: true,
    source: "mapbox_reverse",
    confidence_label: "estimated",
    candidate_reason: "fallback_reverse_geocode",
    reason: "Estimated address from map",
    requires_confirmation: true,
    formatted,
    formatted_address: formatted,
    house_number: reverse.house_number,
    street_name: reverse.street,
    street: reverse.street,
    locality: reverse.locality,
    region: reverse.region,
    postal_code: reverse.postal_code,
    country: reverse.country,
    coordinate: {
      lat: reverse.coordinate.lat,
      lng: reverse.coordinate.lng,
      latitude: reverse.coordinate.lat,
      longitude: reverse.coordinate.lng,
    },
    distance_meters: 0,
    score: 0.35,
  };
}

function ringsForGeometry(geometry: BuildingGeometry): Point[][] {
  if (geometry.type === "Polygon") {
    return (geometry.coordinates as number[][][]).map((ring) => ring as Point[]);
  }
  return (geometry.coordinates as number[][][][]).flatMap((polygon) => polygon.map((ring) => ring as Point[]));
}

function geometryCentroid(geometry: BuildingGeometry): Point | null {
  const points = ringsForGeometry(geometry)
    .flatMap((ring) => {
      const last = ring[ring.length - 1];
      return ring.filter((point, index) => {
        if (index !== ring.length - 1) return true;
        return !last || point[0] !== ring[0]?.[0] || point[1] !== ring[0]?.[1];
      });
    })
    .filter((point) => Number.isFinite(point[0]) && Number.isFinite(point[1]));

  if (points.length === 0) return null;
  const sum = points.reduce((acc, point) => [acc[0] + point[0], acc[1] + point[1]] as Point, [0, 0]);
  return [sum[0] / points.length, sum[1] / points.length];
}

function pointCoordinate(value: unknown): Point | null {
  let raw: unknown;
  try {
    raw = typeof value === "string" ? JSON.parse(value) : value;
  } catch {
    return null;
  }
  if (!raw || typeof raw !== "object") return null;
  const geometry = raw as { type?: unknown; coordinates?: unknown };
  if (geometry.type !== "Point" || !Array.isArray(geometry.coordinates) || geometry.coordinates.length < 2) {
    return null;
  }
  const lng = Number(geometry.coordinates[0]);
  const lat = Number(geometry.coordinates[1]);
  return Number.isFinite(lng) && Number.isFinite(lat) ? [lng, lat] : null;
}

function distanceMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const earthRadiusMeters = 6_371_000;
  const lat1 = a.lat * Math.PI / 180;
  const lat2 = b.lat * Math.PI / 180;
  const dLat = (b.lat - a.lat) * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLng * sinLng;
  return earthRadiusMeters * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

async function orphanCandidatesForUnresolvedBuilding(input: {
  supabase: any;
  campaignId: string;
  buildingId: string;
  buildingIdentifiers: string[];
  seedPoint: { lat: number; lng: number } | null;
  radiusMeters: number;
  limit: number;
  includeLinkedCandidates: boolean;
}): Promise<Array<Record<string, unknown>>> {
  const { supabase, campaignId, buildingId, buildingIdentifiers, seedPoint, radiusMeters, limit, includeLinkedCandidates } = input;
  const currentBuildingIdentifiers = normalizedIdentifierSet(buildingId, ...buildingIdentifiers);
  if (currentBuildingIdentifiers.size === 0) return [];

  const orphanRows = await fetchAllInPages<OrphanRow>((from, to) => supabase
    .from("address_orphans")
    .select("address_id, coordinate, status, nearest_building_id, nearest_distance, suggested_street, address_street")
    .eq("campaign_id", campaignId)
    .in("status", ["pending", "pending_review", "ambiguous_match"])
    .order("nearest_distance", { ascending: true })
    .range(from, to));

  const matchingOrphanRows = orphanRows.filter((row) => {
    const nearestBuildingId = row.nearest_building_id?.trim().toLowerCase();
    return Boolean(nearestBuildingId && currentBuildingIdentifiers.has(nearestBuildingId));
  });

  if (matchingOrphanRows.length === 0) {
    if (!seedPoint) return [];
    return nearbyAddressCandidatesForUnresolvedBuilding({
      supabase,
      campaignId,
      currentBuildingIdentifiers,
      orphanRows,
      seedPoint,
      radiusMeters,
      limit,
      includeLinkedCandidates,
    });
  }

  const addressIds = Array.from(new Set(matchingOrphanRows.map((row) => row.address_id).filter(Boolean)));
  if (addressIds.length === 0) {
    return [];
  }

  const [{ data: addressRows }, { data: linkRows }] = await Promise.all([
    supabase
      .from("campaign_addresses")
      .select("id, formatted, house_number, street_name, source, geom, building_id, building_gers_id")
      .eq("campaign_id", campaignId)
      .in("id", addressIds),
    supabase
      .from("building_address_links")
      .select("address_id, building_id, confidence, match_type")
      .eq("campaign_id", campaignId)
      .in("address_id", addressIds),
  ]);

  const addressesById = new Map<string, AddressRow>(
    ((addressRows ?? []) as AddressRow[]).map((row) => [row.id, row])
  );
  const blockingLinkedAddressIds = new Set(
    ((linkRows ?? []) as LinkRow[])
      .filter((row) => {
        if ((row.match_type ?? "").trim().toLowerCase() === "orphan") return false;
        if (!row.building_id?.trim()) return false;
        if (!includeLinkedCandidates) return true;
        return currentBuildingIdentifiers.has(row.building_id.trim().toLowerCase());
      })
      .map((row) => row.address_id)
  );

  return matchingOrphanRows
    .flatMap((orphan) => {
      if (blockingLinkedAddressIds.has(orphan.address_id)) return [];
      const address = addressesById.get(orphan.address_id);
      if (!address) return [];

      const point = pointCoordinate(address.geom) ?? pointCoordinate(orphan.coordinate);
      if (!point) return [];

      const seedDistance = seedPoint
        ? distanceMeters(seedPoint, { lng: point[0], lat: point[1] })
        : Number(orphan.nearest_distance ?? Number.POSITIVE_INFINITY);
      const candidateDistance = Number.isFinite(Number(orphan.nearest_distance))
        ? Math.min(Number(orphan.nearest_distance), seedDistance)
        : seedDistance;
      if (!Number.isFinite(candidateDistance) || candidateDistance > radiusMeters) return [];

      const score = Math.min(1, Math.max(0, 1 - candidateDistance / Math.max(radiusMeters, 1)) * 0.95 + 0.05);
      const street = address.street_name ?? orphan.suggested_street ?? orphan.address_street ?? null;
      return [{
        id: address.id,
        candidate_type: "official",
        is_synthetic: false,
        formatted: address.formatted,
        formatted_address: address.formatted,
        house_number: address.house_number,
        street_name: street,
        street,
        source: address.source,
        coordinate: { longitude: point[0], latitude: point[1] },
        distance_meters: Math.round(candidateDistance * 10) / 10,
        score: Math.round(score * 1000) / 1000,
        reason: "Nearby orphan address",
        candidate_reason: "pending_orphan_nearest_building",
        confidence_label: candidateDistance <= 25 ? "high" : candidateDistance <= 60 ? "medium" : "low",
        requires_confirmation: candidateDistance > 60,
        trusted: candidateDistance <= 60,
        rejected_reason: candidateDistance > 60 ? "outside_nearby_radius" : null,
      }];
    })
    .sort((a, b) => {
      const distanceDelta = Number(a.distance_meters) - Number(b.distance_meters);
      if (distanceDelta !== 0) return distanceDelta;
      return String(a.formatted ?? "").localeCompare(String(b.formatted ?? ""), undefined, { numeric: true });
    })
    .slice(0, limit);
}

async function nearbyAddressCandidatesForUnresolvedBuilding(input: {
  supabase: any;
  campaignId: string;
  currentBuildingIdentifiers: Set<string>;
  orphanRows: OrphanRow[];
  seedPoint: { lat: number; lng: number };
  radiusMeters: number;
  limit: number;
  includeLinkedCandidates: boolean;
}): Promise<Array<Record<string, unknown>>> {
  const {
    supabase,
    campaignId,
    currentBuildingIdentifiers,
    orphanRows,
    seedPoint,
    radiusMeters,
    limit,
    includeLinkedCandidates,
  } = input;

  const [addressRows, linkRows] = await Promise.all([
    fetchAllInPages<AddressRow>((from, to) => supabase
      .from("campaign_addresses")
      .select("id, formatted, house_number, street_name, source, geom, building_id, building_gers_id")
      .eq("campaign_id", campaignId)
      .order("id", { ascending: true })
      .range(from, to)),
    fetchAllInPages<LinkRow>((from, to) => supabase
      .from("building_address_links")
      .select("address_id, building_id, confidence, match_type")
      .eq("campaign_id", campaignId)
      .order("address_id", { ascending: true })
      .range(from, to)),
  ]);

  const activeOrphansByAddressId = new Map<string, OrphanRow>();
  for (const orphan of orphanRows) {
    const addressId = orphan.address_id?.trim();
    if (!addressId || !pointCoordinate(orphan.coordinate)) continue;
    const existing = activeOrphansByAddressId.get(addressId);
    const existingDistance = Number(existing?.nearest_distance ?? Number.POSITIVE_INFINITY);
    const nextDistance = Number(orphan.nearest_distance ?? Number.POSITIVE_INFINITY);
    if (!existing || nextDistance < existingDistance) {
      activeOrphansByAddressId.set(addressId, orphan);
    }
  }

  const blockingLinkedAddressIds = new Set(
    linkRows
      .filter((row) => {
        if ((row.match_type ?? "").trim().toLowerCase() === "orphan") return false;
        const linkedBuildingId = row.building_id?.trim().toLowerCase();
        if (!linkedBuildingId) return false;
        if (!includeLinkedCandidates) return true;
        return currentBuildingIdentifiers.has(linkedBuildingId);
      })
      .map((row) => row.address_id)
  );

  return addressRows
    .flatMap((address): Array<Record<string, unknown>> => {
      if (blockingLinkedAddressIds.has(address.id)) return [];

      const directIdentifiers = [address.building_id, address.building_gers_id]
        .map((value) => value?.trim().toLowerCase())
        .filter((value): value is string => Boolean(value));
      if (directIdentifiers.some((identifier) => currentBuildingIdentifiers.has(identifier))) return [];

      const orphan = activeOrphansByAddressId.get(address.id);
      const point = pointCoordinate(address.geom) ?? pointCoordinate(orphan?.coordinate);
      if (!point) return [];

      const seedDistance = distanceMeters(seedPoint, { lng: point[0], lat: point[1] });
      if (!Number.isFinite(seedDistance) || seedDistance > radiusMeters) return [];

      const orphanDistance = Number(orphan?.nearest_distance ?? Number.POSITIVE_INFINITY);
      const candidateDistance = Number.isFinite(orphanDistance) ? Math.min(orphanDistance, seedDistance) : seedDistance;
      const score = Math.min(1, Math.max(0, 1 - candidateDistance / Math.max(radiusMeters, 1)) * 0.95 + (address.source?.toLowerCase() === "manual" ? 0.05 : 0));
      const street = address.street_name ?? orphan?.suggested_street ?? orphan?.address_street ?? null;
      return [{
        id: address.id,
        candidate_type: "official",
        is_synthetic: false,
        formatted: address.formatted,
        formatted_address: address.formatted,
        house_number: address.house_number,
        street_name: street,
        street,
        source: address.source,
        coordinate: { longitude: point[0], latitude: point[1] },
        distance_meters: Math.round(candidateDistance * 10) / 10,
        score: Math.round(score * 1000) / 1000,
        reason: orphan ? "Nearby orphan address" : "Nearby campaign address",
        candidate_reason: orphan ? "pending_orphan_nearest_building" : "nearby_seed_address",
        confidence_label: candidateDistance <= 25 ? "high" : candidateDistance <= 60 ? "medium" : "low",
        requires_confirmation: candidateDistance > 60,
        trusted: candidateDistance <= 60,
        rejected_reason: candidateDistance > 60 ? "outside_nearby_radius" : null,
      }];
    })
    .sort((a, b) => {
      const distanceDelta = Number(a.distance_meters) - Number(b.distance_meters);
      if (distanceDelta !== 0) return distanceDelta;
      return String(a.formatted ?? "").localeCompare(String(b.formatted ?? ""), undefined, { numeric: true });
    })
    .slice(0, limit);
}

export async function GET(request: Request, context: RouteContext): Promise<Response> {
  try {
    const token = getAuthToken(request);
    if (!token) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    if (!SUPABASE_URL || !SUPABASE_AUTH_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
      console.error("[address-candidates] Missing Supabase environment", {
        hasUrl: Boolean(SUPABASE_URL),
        hasAuthKey: Boolean(SUPABASE_AUTH_KEY),
        hasServiceRoleKey: Boolean(SUPABASE_SERVICE_ROLE_KEY),
      });
      return NextResponse.json({ error: "Server configuration error" }, { status: 500 });
    }

    const { campaignId, buildingId } = await context.params;
    const url = new URL(request.url);
    const radiusMeters = Math.min(Math.max(Number(url.searchParams.get("radius_m") ?? 60), 1), 120);
    const maxLimit = radiusMeters > 60 ? 20 : 15;
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? maxLimit), 1), maxLimit);
    const forceReverseGeocode = url.searchParams.get("force_reverse_geocode") === "true";
    const includeLinkedCandidates = url.searchParams.get("include_linked_candidates") === "true";
    const requestedBuildingIdentifiers = buildingIdentifiersFromRequest(url, buildingId);
    const seedLat = finiteQueryNumber(url, "seed_lat");
    const seedLng = finiteQueryNumber(url, "seed_lng");
    const seedPoint = seedLat != null && seedLng != null ? { lat: seedLat, lng: seedLng } : null;

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_AUTH_KEY);
    const { data: { user }, error: userError } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const canAccess = await ensureCampaignAccess(supabase, campaignId, user.id);
    if (!canAccess) return NextResponse.json({ error: "Forbidden" }, { status: 403 });

    const building = await resolveBuilding(supabase, campaignId, buildingId);
    if (!building) {
      const orphanCandidates = await orphanCandidatesForUnresolvedBuilding({
        supabase,
        campaignId,
        buildingId,
        buildingIdentifiers: requestedBuildingIdentifiers,
        seedPoint,
        radiusMeters,
        limit,
        includeLinkedCandidates,
      });
      if (orphanCandidates.length > 0) {
        const reverseCandidate = forceReverseGeocode && seedPoint
          ? await reverseCandidatePayload(seedPoint)
          : null;
        return NextResponse.json({
          building_id: buildingId,
          radius_meters: radiusMeters,
          trust_decision: {
            used_reverse_geocode: Boolean(reverseCandidate),
            reason: reverseCandidate
              ? "orphan_candidates_for_static_building_with_reverse_geocode"
              : "orphan_candidates_for_static_building",
            nearest_candidate_distance_m: orphanCandidates[0]?.distance_meters ?? null,
            nearest_candidate_rejected_reason: null,
          },
          candidates: reverseCandidate ? [...orphanCandidates, reverseCandidate] : orphanCandidates,
        });
      }

      if (forceReverseGeocode && seedPoint) {
        const reverseCandidate = await reverseCandidatePayload(seedPoint);
        return NextResponse.json({
          building_id: buildingId,
          radius_meters: radiusMeters,
          trust_decision: {
            used_reverse_geocode: Boolean(reverseCandidate),
            reason: reverseCandidate ? "snapshot_seed_reverse_geocode" : "snapshot_seed_reverse_geocode_unavailable",
            nearest_candidate_distance_m: null,
            nearest_candidate_rejected_reason: null,
          },
          candidates: reverseCandidate ? [reverseCandidate] : [],
        });
      }
      return NextResponse.json({ error: "Building not found" }, { status: 404 });
    }

    const [addressRows, linkRows, orphanRows] = await Promise.all([
      fetchAllInPages<AddressRow>((from, to) => supabase
        .from("campaign_addresses")
        .select("id, formatted, house_number, street_name, source, geom, building_id, building_gers_id")
        .eq("campaign_id", campaignId)
        .order("id", { ascending: true })
        .range(from, to)),
      fetchAllInPages<LinkRow>((from, to) => supabase
        .from("building_address_links")
        .select("address_id, building_id, confidence, match_type")
        .eq("campaign_id", campaignId)
        .order("address_id", { ascending: true })
        .range(from, to)),
      fetchAllInPages<OrphanRow>((from, to) => supabase
        .from("address_orphans")
        .select("address_id, coordinate, status, nearest_building_id, nearest_distance, suggested_street, address_street")
        .eq("campaign_id", campaignId)
        .in("status", ["pending", "pending_review", "ambiguous_match"])
        .order("address_id", { ascending: true })
        .range(from, to)),
    ]);

    const linker = new StableLinkerService(supabase);
    const selection = linker.selectOfficialAddressCandidatesForBuilding({
      building,
      addressRows,
      linkRows,
      orphanRows,
      radiusMeters,
      limit,
      includeLinkedCandidates,
    });
    const trustedCandidate = selection.candidates.find((candidate) => candidate.trusted) ?? null;
    const candidates = selection.candidates as unknown as Array<Record<string, unknown>>;
    const trustDecision: Record<string, unknown> = { ...selection.trustDecision };

    if (forceReverseGeocode || !trustedCandidate) {
      const centroid = geometryCentroid(building.geometry);
      const reversePoint = seedPoint ?? (centroid ? { lng: centroid[0], lat: centroid[1] } : null);
      const reverseCandidate = reversePoint ? await reverseCandidatePayload(reversePoint) : null;
      if (reverseCandidate) {
        trustDecision.used_reverse_geocode = true;
        candidates.push(reverseCandidate);
      } else {
        trustDecision.reason = `${String(trustDecision.reason)}_reverse_geocode_unavailable`;
      }
    }

    return NextResponse.json({
      building_id: building.publicId,
      radius_meters: radiusMeters,
      trust_decision: trustDecision,
      candidates,
    });
  } catch (error) {
    console.error("[address-candidates] GET error:", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
