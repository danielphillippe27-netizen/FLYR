import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import {
  getGoldAddressesForPolygon,
  insertCampaignAddresses,
  type NormalizedCampaignAddress,
} from "../../../../lib/services/GoldAddressService";
import {
  generateSnapshots,
  fetchGeoJSONFromUrl,
  type GeoJSONFeature,
  type GeoJSONFeatureCollection,
} from "../../../../lib/services/TileLambdaService";
import {
  fetchAndNormalize,
  fromGoldFeatureCollection,
} from "../../../../lib/services/BuildingAdapter";
import { runSpatialJoin } from "../../../../lib/services/StableLinkerService";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SNAPSHOT_BUCKET = process.env.SNAPSHOT_BUCKET ?? "flyr-snapshots";
const DEFAULT_SILVER_ADDRESS_LIMIT = 2500;

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

interface CampaignRow {
  id:                 string;
  owner_id:           string;
  territory_boundary: unknown;
  region:             string | null;
  provision_status:   string | null;
  address_source:     string | null;
}

interface RoadMetadataRow {
  roads_status: string;
  road_count:   number;
}

interface ReadinessChecks {
  addresses_saved_gt_0: boolean;
  map_roads_ready?:     boolean;
  roads_status?:        string | null;
  road_count?:          number;
}

type DataConfidenceLabel = "low" | "medium" | "high";

interface DataConfidenceMetrics {
  addresses_total: number;
  addresses_linked: number;
  linked_coverage: number;
  building_link_count: number;
  gold_exact_count: number;
  gold_proximity_count: number;
  gold_unlinked_count: number;
  silver_count: number;
  bronze_count: number;
  lambda_count: number;
  manual_count: number;
  other_count: number;
  unlinked_count: number;
  avg_address_score: number;
  avg_link_confidence: number;
}

interface DataConfidenceSummary {
  version: 1;
  score: number;
  label: DataConfidenceLabel;
  reason: string;
  metrics: DataConfidenceMetrics;
  calculated_at: string;
}

interface CampaignAddressConfidenceRow {
  id: string;
  source: string | null;
  match_source: string | null;
  confidence: number | string | null;
  building_id: string | null;
}

interface BuildingLinkConfidenceRow {
  address_id: string;
  confidence_score: number | string | null;
}

/**
 * POST /api/campaigns/provision
 * Body: { campaign_id: string }
 *
 * Orchestrates Gold vs Lambda address/building provisioning:
 *   1. Load campaign (territory_boundary, region).
 *   2. Set provision_status = 'pending'.
 *   3. Query Gold addresses.
 *   4a. Gold path (>= 10 Gold addresses):
 *       - Query Gold buildings.
 *       - Insert addresses into campaign_addresses.
 *       - Run link_campaign_addresses_gold RPC.
 *   4b. Lambda path (< 10 Gold):
 *       - Call Tile Lambda (generateSnapshots).
 *       - Download + merge addresses (Gold + Lambda if any Gold found).
 *       - Insert addresses into campaign_addresses.
 *       - Download Lambda buildings GeoJSON.
 *       - Run StableLinkerService (JS spatial join → building_address_links).
 *       - Write campaign_snapshots row.
 *   5. Set provision_status = 'ready'.
 *   6. Validate readiness (addresses > 0; for address_source=map, roads metadata ready + road_count > 0).
 *   7. Set provision_status = 'ready' only if checks pass; else 'failed' and 422.
 *   8. Return { success, addresses_saved, buildings_saved, roads_count, readiness_checks }.
 */
export async function POST(request: Request): Promise<Response> {
  const supabase = adminClient();

  // Auth
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: { user }, error: userError } = await anonClient.auth.getUser(token);
  if (userError || !user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Parse body
  let campaignId: string;
  try {
    const body = await request.json() as { campaign_id?: string };
    campaignId = body.campaign_id ?? "";
  } catch {
    return NextResponse.json({ error: "Invalid JSON body; expected { campaign_id }" }, { status: 400 });
  }
  if (!campaignId) {
    return NextResponse.json({ error: "Missing campaign_id" }, { status: 400 });
  }

  // Load campaign
  const { data: campaign, error: campErr } = await supabase
    .from("campaigns")
    .select("id, owner_id, territory_boundary, region, provision_status, address_source")
    .eq("id", campaignId)
    .maybeSingle();

  if (campErr || !campaign) {
    return NextResponse.json({ error: "Campaign not found" }, { status: 404 });
  }

  const c = campaign as CampaignRow;

  // Access check (owner or workspace member via RLS — service role bypasses, so check manually)
  if (c.owner_id !== user.id) {
    // Check workspace membership
    const { data: wsCamp } = await supabase
      .from("campaigns")
      .select("workspace_id")
      .eq("id", campaignId)
      .maybeSingle();
    const wsId = (wsCamp as { workspace_id: string | null } | null)?.workspace_id;
    if (wsId) {
      const { data: member } = await supabase
        .from("workspace_members")
        .select("user_id")
        .eq("workspace_id", wsId)
        .eq("user_id", user.id)
        .maybeSingle();
      if (!member) {
        return NextResponse.json({ error: "Forbidden" }, { status: 403 });
      }
    } else {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
  }

  if (!c.territory_boundary) {
    return NextResponse.json(
      { error: "No territory boundary defined. Please draw a polygon on the map when creating the campaign." },
      { status: 400 }
    );
  }

  // Set provision_status = 'pending'
  await supabase
    .from("campaigns")
    .update({ provision_status: "pending" })
    .eq("id", campaignId);

  const polygonGeoJSON =
    typeof c.territory_boundary === "string"
      ? c.territory_boundary
      : JSON.stringify(c.territory_boundary);

  const province = c.region ?? undefined;
  console.log(
    `[Provision] Campaign context: boundary_type=${typeof c.territory_boundary} province=${province ?? "null"}`
  );

  try {
    // -------------------------------------------------------------------------
    // Step 1: Query Gold addresses
    // -------------------------------------------------------------------------
    const goldResult = await getGoldAddressesForPolygon(
      campaignId,
      c.owner_id,
      polygonGeoJSON,
      province
    );

    let addressesSaved = 0;
    let buildingsSaved = 0;

    if (goldResult.source === "gold") {
      // -----------------------------------------------------------------------
      // Gold path
      // -----------------------------------------------------------------------
      console.log(`[Provision] Gold path: ${goldResult.goldCount} addresses`);

      // Fetch Gold buildings
      const { data: goldBuildingsRaw, error: bErr } = await supabase
        .rpc("get_gold_buildings_in_polygon_geojson", {
          p_polygon_geojson: polygonGeoJSON,
        });

      if (bErr) {
        console.warn("[Provision] Gold buildings RPC error:", bErr);
      }

      const goldBuildingsGeo = normalizeGoldBuildingsRpc(goldBuildingsRaw);
      buildingsSaved = goldBuildingsGeo?.features.length ?? 0;

      // Insert addresses
      addressesSaved = await insertCampaignAddresses(campaignId, goldResult.addresses);

      // Run Gold linker (SQL, sets campaign_addresses.building_id)
      let { data: linkResult, error: linkErr } = await supabase
        .rpc("link_campaign_addresses_gold", {
          p_campaign_id:     campaignId,
          p_polygon_geojson: polygonGeoJSON,
        });

      if (linkErr && isMissingTwoArgLinkerError(linkErr.message ?? "")) {
        const oneArg = await supabase.rpc("link_campaign_addresses_gold", {
          p_campaign_id: campaignId,
        });
        linkResult = oneArg.data;
        linkErr = oneArg.error;
      }

      if (linkErr) {
        console.warn("[Provision] Gold linker error:", linkErr);
      } else {
        const linked = parseTotalLinked(linkResult);
        if (linked !== null) {
          console.log(`[Provision] Gold linker linked ${linked} addresses`);
        } else {
          console.log("[Provision] Gold linker completed");
        }
      }

    } else {
      // -----------------------------------------------------------------------
      // Lambda path
      // -----------------------------------------------------------------------
      console.log("[Provision] Lambda path");

      const snapshot = await generateSnapshots({
        campaign_id:     campaignId,
        polygon_geojson: polygonGeoJSON,
        province,
        address_limit:   DEFAULT_SILVER_ADDRESS_LIMIT,
      });

      // Download addresses from Lambda
      let lambdaAddresses: NormalizedCampaignAddress[] = [];
      if (snapshot.urls.addresses) {
        const lambdaAddrGeo = await fetchGeoJSONFromUrl(snapshot.urls.addresses);
        lambdaAddresses = lambdaAddrGeo.features.map((f) => {
          const p = f.properties ?? {};
          const coords = (f.geometry as { coordinates?: [number, number] })?.coordinates;
          return {
            campaign_id:  campaignId,
            owner_id:     c.owner_id,
            house_number: (p.house_number ?? p.street_number ?? null) as string | null,
            street_name:  (p.street_name ?? null) as string | null,
            locality:     (p.city ?? p.locality ?? null) as string | null,
            region:       (p.province ?? p.region ?? null) as string | null,
            postal_code:  (p.zip ?? p.postal_code ?? null) as string | null,
            country:      (p.country ?? null) as string | null,
            formatted:    (p.formatted ?? p.label ?? "") as string,
            geom:         coords
              ? JSON.stringify({ type: "Point", coordinates: coords })
              : null,
            gers_id:      (p.gers_id ?? p.id ?? null) as string | null,
            source:       "lambda" as const,
          };
        });
      }

      // Merge: Gold addresses (if any) override Lambda by street+number
      const allAddresses: NormalizedCampaignAddress[] =
        goldResult.goldCount > 0
          ? mergeAddresses(goldResult.addresses, lambdaAddresses)
          : lambdaAddresses;
      console.log(
        `[Provision] Lambda merge: gold_candidates=${goldResult.addresses.length} lambda_addresses=${lambdaAddresses.length} merged=${allAddresses.length}`
      );
      if (allAddresses.length === 0) {
        console.warn(
          `[Provision] No addresses returned by Gold or Lambda for campaign ${campaignId}`
        );
      }

      addressesSaved = await insertCampaignAddresses(campaignId, allAddresses);

      // Download Lambda buildings GeoJSON
      let lambdaBuildingsGeo: GeoJSONFeatureCollection | null = null;
      if (snapshot.urls.buildings) {
        lambdaBuildingsGeo = await fetchGeoJSONFromUrl(snapshot.urls.buildings);
        buildingsSaved = lambdaBuildingsGeo.features.length;
      }

      // Run JS spatial join → building_address_links
      if (lambdaBuildingsGeo && lambdaBuildingsGeo.features.length > 0) {
        await runSpatialJoin(campaignId, lambdaBuildingsGeo);
      }

      // Write campaign_snapshots
      if (snapshot.keys.buildings_key || snapshot.keys.addresses_key) {
        await supabase
          .from("campaign_snapshots")
          .upsert(
            {
              campaign_id:      campaignId,
              bucket:           snapshot.bucket ?? SNAPSHOT_BUCKET,
              buildings_key:    snapshot.keys.buildings_key ?? null,
              addresses_key:    snapshot.keys.addresses_key ?? null,
              buildings_count:  buildingsSaved,
              addresses_count:  addressesSaved,
            },
            { onConflict: "campaign_id" }
          );
      }
    }

    const confidenceSummary = await buildCampaignDataConfidence(supabase, campaignId);

    // -------------------------------------------------------------------------
    // Readiness: addresses required; map-sourced campaigns require road metadata
    // -------------------------------------------------------------------------
    const addressSource = (c.address_source ?? "").toLowerCase();
    const isMapSourced = addressSource === "map";

    const { data: roadMetaRow } = await supabase
      .from("campaign_road_metadata")
      .select("roads_status, road_count")
      .eq("campaign_id", campaignId)
      .maybeSingle();

    const roadMeta = roadMetaRow as RoadMetadataRow | null;
    const roadsCount = roadMeta?.road_count ?? 0;
    const roadsStatus = roadMeta?.roads_status ?? null;
    const mapRoadsOk =
      !isMapSourced ||
      (roadsStatus === "ready" && roadsCount > 0);

    const readinessChecks: ReadinessChecks = {
      addresses_saved_gt_0: addressesSaved > 0,
      ...(isMapSourced
        ? {
            map_roads_ready: mapRoadsOk,
            roads_status:    roadsStatus,
            road_count:      roadsCount,
          }
        : {}),
    };

    const failProvision = async (
      message: string,
      checks: ReadinessChecks,
      confidence: DataConfidenceSummary
    ): Promise<Response> => {
      await supabase
        .from("campaigns")
        .update({
          provision_status: "failed",
          data_confidence_score: confidence.score,
          data_confidence_label: confidence.label,
          data_confidence_reason: confidence.reason,
          data_confidence_summary: confidence,
          data_confidence_updated_at: confidence.calculated_at,
        })
        .eq("id", campaignId);
      console.warn(`[Provision] Readiness failed: campaign=${campaignId} ${message}`, checks);
      return NextResponse.json(
        {
          success:          false,
          error:            message,
          addresses_saved:  addressesSaved,
          buildings_saved:  buildingsSaved,
          roads_count:      roadsCount,
          readiness_checks: checks,
          data_confidence_score: confidence.score,
          data_confidence_label: confidence.label,
          data_confidence_reason: confidence.reason,
          data_confidence_summary: confidence,
        },
        { status: 422 }
      );
    };

    if (addressesSaved <= 0) {
      return await failProvision(
        "No addresses were saved for this campaign. Try a larger area or verify territory boundaries.",
        readinessChecks,
        confidenceSummary
      );
    }

    if (isMapSourced && !mapRoadsOk) {
      return await failProvision(
        "Campaign roads are not ready in the database (map campaigns require roads before provisioning completes). Open the campaign to refresh roads, then retry provisioning.",
        readinessChecks,
        confidenceSummary
      );
    }

    // -------------------------------------------------------------------------
    // Set provision_status = 'ready'
    // -------------------------------------------------------------------------
    await supabase
      .from("campaigns")
      .update({
        provision_status:           "ready",
        provisioned_at:             new Date().toISOString(),
        data_confidence_score:      confidenceSummary.score,
        data_confidence_label:      confidenceSummary.label,
        data_confidence_reason:     confidenceSummary.reason,
        data_confidence_summary:    confidenceSummary,
        data_confidence_updated_at: confidenceSummary.calculated_at,
      })
      .eq("id", campaignId);

    console.log(
      `[Provision] Done: campaign=${campaignId} addresses=${addressesSaved} buildings=${buildingsSaved} roads_count=${roadsCount}`
    );

    return NextResponse.json({
      success:          true,
      addresses_saved:  addressesSaved,
      buildings_saved:  buildingsSaved,
      roads_count:      roadsCount,
      readiness_checks: readinessChecks,
      data_confidence_score: confidenceSummary.score,
      data_confidence_label: confidenceSummary.label,
      data_confidence_reason: confidenceSummary.reason,
      data_confidence_summary: confidenceSummary,
      message:          `Provisioning complete: ${addressesSaved} addresses, ${buildingsSaved} buildings`,
    });

  } catch (err) {
    console.error("[Provision] Error:", err);
    await supabase
      .from("campaigns")
      .update({ provision_status: "failed" })
      .eq("id", campaignId);

    return NextResponse.json(
      { error: "Provisioning failed", details: String(err) },
      { status: 500 }
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Merges Gold addresses with Lambda addresses.
 * Gold wins on conflict (matched by normalized street + house number).
 */
function mergeAddresses(
  gold:   NormalizedCampaignAddress[],
  lambda: NormalizedCampaignAddress[]
): NormalizedCampaignAddress[] {
  const goldKeys = new Set(
    gold.map((a) =>
      `${(a.house_number ?? "").toLowerCase()}|${(a.street_name ?? "").toLowerCase()}`
    )
  );
  const merged = [...gold];
  for (const a of lambda) {
    const key = `${(a.house_number ?? "").toLowerCase()}|${(a.street_name ?? "").toLowerCase()}`;
    if (!goldKeys.has(key)) {
      merged.push({ ...a, source: "silver" });
    }
  }
  return merged;
}

function parseNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function roundMetric(value: number, digits = 3): number {
  return Number(value.toFixed(digits));
}

function percent(count: number, total: number): number {
  if (total <= 0) return 0;
  return Math.round((count / total) * 100);
}

function confidenceLabelForScore(score: number): DataConfidenceLabel {
  if (score >= 0.85) return "high";
  if (score >= 0.65) return "medium";
  return "low";
}

function sourceWeight(row: CampaignAddressConfidenceRow): number {
  const matchSource = (row.match_source ?? "").toLowerCase();
  const source = (row.source ?? "").toLowerCase();
  const confidence = clamp01(parseNumber(row.confidence) ?? 0.5);

  if (matchSource === "gold_exact") return 1.0;
  if (matchSource === "gold_proximity") return 0.7 + (confidence * 0.3);

  switch (source) {
    case "gold":
      return 0.72;
    case "silver":
      return 0.68;
    case "bronze":
      return 0.5;
    case "lambda":
      return 0.62;
    case "manual":
      return 0.95;
    default:
      return 0.5;
  }
}

function buildConfidenceReason(metrics: DataConfidenceMetrics): string {
  const total = metrics.addresses_total;
  if (total <= 0) {
    return "No addresses were provisioned, so confidence could not be established.";
  }

  const parts: string[] = [];
  const candidates: Array<{ count: number; label: string }> = [
    { count: metrics.gold_exact_count, label: "gold exact" },
    { count: metrics.gold_proximity_count, label: "gold proximity" },
    { count: metrics.silver_count, label: "silver" },
    { count: metrics.bronze_count, label: "bronze" },
    { count: metrics.lambda_count, label: "lambda" },
    { count: metrics.gold_unlinked_count, label: "gold unlinked" },
    { count: metrics.manual_count, label: "manual" },
  ];

  for (const candidate of candidates) {
    if (candidate.count > 0) {
      parts.push(`${percent(candidate.count, total)}% ${candidate.label}`);
    }
    if (parts.length === 3) break;
  }

  if (metrics.unlinked_count > 0) {
    parts.push(`${percent(metrics.unlinked_count, total)}% unlinked`);
  }

  parts.push(`${percent(metrics.addresses_linked, total)}% linked to buildings`);
  return parts.join(", ");
}

async function buildCampaignDataConfidence(
  supabase: ReturnType<typeof adminClient>,
  campaignId: string
): Promise<DataConfidenceSummary> {
  const [addressRes, linkRes] = await Promise.all([
    supabase
      .from("campaign_addresses")
      .select("id, source, match_source, confidence, building_id")
      .eq("campaign_id", campaignId),
    supabase
      .from("building_address_links")
      .select("address_id, confidence_score")
      .eq("campaign_id", campaignId),
  ]);

  if (addressRes.error) {
    throw new Error(`[Provision] Failed to load campaign_addresses for confidence: ${addressRes.error.message}`);
  }
  if (linkRes.error) {
    throw new Error(`[Provision] Failed to load building_address_links for confidence: ${linkRes.error.message}`);
  }

  const addresses = (addressRes.data ?? []) as CampaignAddressConfidenceRow[];
  const links = (linkRes.data ?? []) as BuildingLinkConfidenceRow[];

  if (addresses.length === 0) {
    return {
      version: 1,
      score: 0,
      label: "low",
      reason: "No addresses were provisioned, so confidence could not be established.",
      metrics: {
        addresses_total: 0,
        addresses_linked: 0,
        linked_coverage: 0,
        building_link_count: links.length,
        gold_exact_count: 0,
        gold_proximity_count: 0,
        gold_unlinked_count: 0,
        silver_count: 0,
        bronze_count: 0,
        lambda_count: 0,
        manual_count: 0,
        other_count: 0,
        unlinked_count: 0,
        avg_address_score: 0,
        avg_link_confidence: 0,
      },
      calculated_at: new Date().toISOString(),
    };
  }

  const linkConfidenceByAddress = new Map<string, number>();
  for (const link of links) {
    const parsed = clamp01(parseNumber(link.confidence_score) ?? 0.65);
    if (!linkConfidenceByAddress.has(link.address_id)) {
      linkConfidenceByAddress.set(link.address_id, parsed);
    }
  }

  let weightedScoreTotal = 0;
  let linkedCount = 0;
  let linkedConfidenceTotal = 0;
  let goldExactCount = 0;
  let goldProximityCount = 0;
  let goldUnlinkedCount = 0;
  let silverCount = 0;
  let bronzeCount = 0;
  let lambdaCount = 0;
  let manualCount = 0;
  let otherCount = 0;

  for (const address of addresses) {
    const matchSource = (address.match_source ?? "").toLowerCase();
    const source = (address.source ?? "").toLowerCase();
    const linked = Boolean(address.building_id) || linkConfidenceByAddress.has(address.id);

    weightedScoreTotal += sourceWeight(address);

    if (matchSource === "gold_exact") {
      goldExactCount += 1;
    } else if (matchSource === "gold_proximity") {
      goldProximityCount += 1;
    } else if (source === "gold") {
      goldUnlinkedCount += 1;
    } else if (source === "silver") {
      silverCount += 1;
    } else if (source === "bronze") {
      bronzeCount += 1;
    } else if (source === "lambda") {
      lambdaCount += 1;
    } else if (source === "manual") {
      manualCount += 1;
    } else {
      otherCount += 1;
    }

    if (linked) {
      linkedCount += 1;

      if (matchSource === "gold_exact") {
        linkedConfidenceTotal += 1.0;
      } else if (matchSource === "gold_proximity") {
        linkedConfidenceTotal += clamp01(parseNumber(address.confidence) ?? 0.7);
      } else if (linkConfidenceByAddress.has(address.id)) {
        linkedConfidenceTotal += linkConfidenceByAddress.get(address.id) ?? 0.65;
      } else {
        linkedConfidenceTotal += 0.7;
      }
    }
  }

  const addressesTotal = addresses.length;
  const unlinkedCount = Math.max(0, addressesTotal - linkedCount);
  const linkedCoverage = linkedCount / addressesTotal;
  const avgAddressScore = weightedScoreTotal / addressesTotal;
  const avgLinkConfidence = linkedCount > 0 ? linkedConfidenceTotal / linkedCount : 0;
  const coverageFactor = 0.8 + (0.2 * linkedCoverage);
  const linkFactor = linkedCount > 0 ? 0.9 + (0.1 * avgLinkConfidence) : 0.85;
  const score = clamp01(avgAddressScore * coverageFactor * linkFactor);
  const metrics: DataConfidenceMetrics = {
    addresses_total: addressesTotal,
    addresses_linked: linkedCount,
    linked_coverage: roundMetric(linkedCoverage),
    building_link_count: links.length,
    gold_exact_count: goldExactCount,
    gold_proximity_count: goldProximityCount,
    gold_unlinked_count: goldUnlinkedCount,
    silver_count: silverCount,
    bronze_count: bronzeCount,
    lambda_count: lambdaCount,
    manual_count: manualCount,
    other_count: otherCount,
    unlinked_count: unlinkedCount,
    avg_address_score: roundMetric(avgAddressScore),
    avg_link_confidence: roundMetric(avgLinkConfidence),
  };

  return {
    version: 1,
    score: roundMetric(score),
    label: confidenceLabelForScore(score),
    reason: buildConfidenceReason(metrics),
    metrics,
    calculated_at: new Date().toISOString(),
  };
}

function parseTotalLinked(raw: unknown): number | null {
  const row = (Array.isArray(raw) ? raw[0] : raw) as Record<string, unknown> | null | undefined;
  if (!row || typeof row !== "object") return null;

  const total = parseNumber(row.total_linked);
  if (total !== null) return total;

  const exact = parseNumber(row.linked_exact) ?? parseNumber(row.exact_matches) ?? 0;
  const proximity = parseNumber(row.linked_proximity) ?? parseNumber(row.proximity_matches) ?? 0;
  return exact + proximity;
}

function isMissingTwoArgLinkerError(message: string): boolean {
  return (
    message.includes("Could not find the function public.link_campaign_addresses_gold") &&
    message.includes("p_polygon_geojson")
  );
}

function normalizeGoldBuildingsRpc(raw: unknown): GeoJSONFeatureCollection | null {
  if (!raw) return null;

  if (typeof raw === "string") {
    try {
      return normalizeGoldBuildingsRpc(JSON.parse(raw));
    } catch {
      return null;
    }
  }

  if (Array.isArray(raw)) {
    if (raw.length === 0) {
      return { type: "FeatureCollection", features: [] };
    }

    const first = raw[0] as Record<string, unknown>;
    if (first?.type === "Feature") {
      return { type: "FeatureCollection", features: raw as GeoJSONFeature[] };
    }

    const features: GeoJSONFeature[] = raw
      .map((entry) => toFeatureFromGoldBuildingRow(entry as Record<string, unknown>))
      .filter((f): f is GeoJSONFeature => f !== null);

    return { type: "FeatureCollection", features };
  }

  if (typeof raw === "object") {
    const obj = raw as Record<string, unknown>;

    if ("get_gold_buildings_in_polygon_geojson" in obj) {
      return normalizeGoldBuildingsRpc(obj.get_gold_buildings_in_polygon_geojson);
    }

    if (obj.type === "FeatureCollection" && Array.isArray(obj.features)) {
      return {
        type: "FeatureCollection",
        features: obj.features as GeoJSONFeature[],
      };
    }

    if (obj.type === "Feature") {
      return {
        type: "FeatureCollection",
        features: [obj as unknown as GeoJSONFeature],
      };
    }
  }

  return null;
}

function toFeatureFromGoldBuildingRow(
  row: Record<string, unknown>
): GeoJSONFeature | null {
  const rawGeom = row.geom_geojson ?? row.geometry;
  const geometry = parseGeometry(rawGeom);
  if (!geometry) return null;

  return {
    type: "Feature",
    id: (row.id as string | number | undefined) ?? undefined,
    geometry,
    properties: {
      ...row,
      source: "gold",
    } as Record<string, unknown>,
  };
}

function parseGeometry(
  raw: unknown
): { type: string; coordinates: unknown } | null {
  if (!raw) return null;

  if (typeof raw === "string") {
    try {
      return parseGeometry(JSON.parse(raw));
    } catch {
      return null;
    }
  }

  if (typeof raw === "object") {
    const obj = raw as Record<string, unknown>;
    if (typeof obj.type === "string" && "coordinates" in obj) {
      return {
        type: obj.type,
        coordinates: obj.coordinates,
      };
    }
  }

  return null;
}
