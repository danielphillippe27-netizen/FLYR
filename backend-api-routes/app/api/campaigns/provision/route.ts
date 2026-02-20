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

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

interface CampaignRow {
  id:                 string;
  owner_id:           string;
  territory_boundary: unknown;
  region:             string | null;
  provision_status:   string | null;
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
 *   6. Return { success, addresses_saved, buildings_saved }.
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
    .select("id, owner_id, territory_boundary, region, provision_status")
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
        })
        .single();

      if (bErr) {
        console.warn("[Provision] Gold buildings RPC error:", bErr);
      }

      const goldBuildingsGeo = goldBuildingsRaw as GeoJSONFeatureCollection | null;
      buildingsSaved = goldBuildingsGeo?.features.length ?? 0;

      // Insert addresses
      addressesSaved = await insertCampaignAddresses(campaignId, goldResult.addresses);

      // Run Gold linker (SQL, sets campaign_addresses.building_id)
      const { data: linkResult, error: linkErr } = await supabase
        .rpc("link_campaign_addresses_gold", {
          p_campaign_id:     campaignId,
          p_polygon_geojson: polygonGeoJSON,
        })
        .single();

      if (linkErr) {
        console.warn("[Provision] Gold linker error:", linkErr);
      } else {
        const linked = (linkResult as { total_linked?: number } | null)?.total_linked ?? 0;
        console.log(`[Provision] Gold linker linked ${linked} addresses`);
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

    // -------------------------------------------------------------------------
    // Set provision_status = 'ready'
    // -------------------------------------------------------------------------
    await supabase
      .from("campaigns")
      .update({
        provision_status: "ready",
        provisioned_at:   new Date().toISOString(),
      })
      .eq("id", campaignId);

    console.log(
      `[Provision] Done: campaign=${campaignId} addresses=${addressesSaved} buildings=${buildingsSaved}`
    );

    return NextResponse.json({
      success:         true,
      addresses_saved: addressesSaved,
      buildings_saved: buildingsSaved,
      message:         `Provisioning complete: ${addressesSaved} addresses, ${buildingsSaved} buildings`,
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
